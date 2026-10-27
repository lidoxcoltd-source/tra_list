const { createHash, randomBytes } = require("node:crypto");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getStorage } = require("firebase-admin/storage");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();

// Status expiry is derived from Firestore's server createTime, never the
// publishing device's clock.
exports.setMarketStatusExpiry = onDocumentCreated(
  'marketPosts/{postId}',
  async (event) => {
    const snapshot = event.data;
    const data = snapshot?.data();
    if (!snapshot || data?.type !== 'status') return;
    await snapshot.ref.update({
      createdAt: snapshot.createTime,
      expiresAt: Timestamp.fromMillis(
        snapshot.createTime.toMillis() + 24 * 60 * 60 * 1000,
      ),
    });
  },
);

exports.cleanupMarketPostChildren = onDocumentDeleted(
  "marketPosts/{postId}",
  async (event) => {
    const reference = event.data?.ref;
    if (!reference) return;
    const collections = await reference.listCollections();
    for (const collection of collections) {
      while (true) {
        const snapshot = await collection.limit(400).get();
        if (snapshot.empty) break;
        const batch = db.batch();
        for (const child of snapshot.docs) batch.delete(child.ref);
        await batch.commit();
        if (snapshot.size < 400) break;
      }
    }
  },
);

exports.ensureMarketPublicProfile = onDocumentCreated(
  "marketPosts/{postId}",
  async (event) => {
    const post = event.data?.data();
    if (!post?.authorUid) return;
    const profileRef = db.collection("publicProfiles").doc(post.authorUid);
    const existing = await profileRef.get();
    const name = String(post.authorName || "MJASI user").trim().slice(0, 80);
    const [postCount, followerCount, followingCount] = await Promise.all([
      db
        .collection("marketPosts")
        .where("authorUid", "==", post.authorUid)
        .where("type", "in", ["post", "product"])
        .count()
        .get(),
      db
        .collectionGroup("following")
        .where("followingUid", "==", post.authorUid)
        .count()
        .get(),
      db
        .collectionGroup("following")
        .where("followerUid", "==", post.authorUid)
        .count()
        .get(),
    ]);
    if (existing.exists) {
      await profileRef.update({
        postsCount: postCount.data().count,
        followersCount: followerCount.data().count,
        followingCount: followingCount.data().count,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      await profileRef.set({
        name,
        nameLower: name.toLowerCase(),
        category: String(post.category || ""),
        bio: "",
        city: "",
        photoUrl: String(post.authorPhotoUrl || ""),
        whatsapp: String(post.whatsapp || ""),
        followersCount: followerCount.data().count,
        followingCount: followingCount.data().count,
        postsCount: postCount.data().count,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  },
);

exports.refreshMarketPostCountOnDelete = onDocumentDeleted(
  "marketPosts/{postId}",
  async (event) => {
    const post = event.data?.data();
    if (!post?.authorUid || post.type === "status") return;
    const profile = db.collection("publicProfiles").doc(post.authorUid);
    const currentProfile = await profile.get();
    if (!currentProfile.exists) return;
    const count = await db
      .collection("marketPosts")
      .where("authorUid", "==", post.authorUid)
      .where("type", "in", ["post", "product"])
      .count()
      .get();
    await profile.update({ postsCount: count.data().count });
  },
);

exports.cleanupExpiredMarketStatuses = onSchedule(
  "every 60 minutes",
  async () => {
    const now = Timestamp.now();
    const expired = await db
      .collection("marketPosts")
      .where("type", "==", "status")
      .where("expiresAt", "<=", now)
      .limit(200)
      .get();
    const bucket = getStorage().bucket();

    for (const status of expired.docs) {
      const images = Array.isArray(status.data().images) ? status.data().images : [];
      for (const imageUrl of images) {
        try {
          const imageUri = new URL(String(imageUrl));
          if (imageUri.hostname !== "firebasestorage.googleapis.com") continue;
          const objectPath = decodeURIComponent(imageUri.pathname.split("/o/")[1] || "");
          if (!objectPath.startsWith(`market/${status.data().authorUid}/`)) continue;
          const references = await db
            .collection("marketPosts")
            .where("images", "array-contains", imageUrl)
            .limit(2)
            .get();
          if (references.size === 1 && references.docs[0].id === status.id && objectPath) {
            await bucket.file(objectPath).delete({ ignoreNotFound: true });
          }
        } catch (error) {
          console.warn("Expired status image cleanup skipped", error);
        }
      }

      const videoUrl = status.data().videoUrl;
      if (videoUrl) {
        try {
          const videoUri = new URL(String(videoUrl));
          const videoPath = decodeURIComponent(videoUri.pathname.split("/o/")[1] || "");
          const shared = await db
            .collection("marketPosts")
            .where("videoUrl", "==", videoUrl)
            .limit(2)
            .get();
          if (
            videoPath.startsWith(`market/${status.data().authorUid}/video/`) &&
            shared.size === 1 && shared.docs[0].id === status.id
          ) {
            await bucket.file(videoPath).delete({ ignoreNotFound: true });
          }
        } catch (error) {
          console.warn("Expired status video cleanup skipped", error);
        }
      }

      const childCollections = await status.ref.listCollections();
      for (const collection of childCollections) {
        const children = await collection.get();
        for (let offset = 0; offset < children.docs.length; offset += 400) {
          const batch = db.batch();
          for (const child of children.docs.slice(offset, offset + 400)) {
            batch.delete(child.ref);
          }
          await batch.commit();
        }
      }
      await status.ref.delete();
    }
  },
);

exports.syncMarketInventoryProduct = onDocumentWritten(
  "users/{businessUid}/products/{productId}",
  async (event) => {
    const after = event.data?.after;
    const product = after?.exists ? after.data() : null;
    const posts = await db
      .collection("marketPosts")
      .where("productOwnerUid", "==", event.params.businessUid)
      .where("productId", "==", event.params.productId)
      .get();
    if (posts.empty) return;

    const available = product
      ? product.active !== false && (product.tracked === false || Number(product.quantity || 0) > 0)
      : false;
    for (let offset = 0; offset < posts.docs.length; offset += 400) {
      const batch = db.batch();
      for (const post of posts.docs.slice(offset, offset + 400)) {
        batch.update(post.ref, {
          inStock: available,
          ...(product && typeof product.sellPrice === "number"
            ? { price: product.sellPrice }
            : {}),
          ...(product?.name ? { productName: String(product.name).slice(0, 120) } : {}),
        });
      }
      await batch.commit();
    }
  },
);

async function updateMarketCount(postId, field, delta, eventId) {
  const ref = db.collection("marketPosts").doc(postId);
  const eventRef = db.collection("marketCounterEvents").doc(eventId);
  await db.runTransaction(async (transaction) => {
    const [eventSnapshot, snapshot] = await Promise.all([
      transaction.get(eventRef),
      transaction.get(ref),
    ]);
    if (eventSnapshot.exists || !snapshot.exists) return;
    const current = Number(snapshot.data()?.[field] || 0);
    transaction.create(eventRef, {
      createdAt: FieldValue.serverTimestamp(),
      postId,
      field,
      delta,
    });
    transaction.update(ref, { [field]: Math.max(0, current + delta) });
  });
}

async function sendMarketActivity(uid, body, postId, kind, eventId, actorUid = "") {
  const [businessProfile, personalProfile] = await Promise.all([
    db.doc(`users/${uid}/profile/company`).get(),
    db.doc(`personalUsers/${uid}`).get(),
  ]);
  if (
    businessProfile.data()?.notificationsEnabled === false ||
    personalProfile.data()?.notificationsEnabled === false
  ) {
    return;
  }
  const ref = db
    .collection("userNotifications")
    .doc(uid)
    .collection("items")
    .doc(eventId);
  const created = await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return false;
    transaction.create(ref, {
      body,
      postId,
      kind,
      ...(actorUid ? { actorUid } : {}),
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!created) return;
  const tokenDocs = await db.collection("deviceTokens").where("uid", "==", uid).get();
  const tokens = tokenDocs.docs.map((doc) => doc.id);
  if (tokens.length) {
    await sendToTokens(tokens, "MJASI MARKET", body, {
      type: "market",
      postId,
      ...(actorUid ? { actorUid } : {}),
    });
  }
}

exports.countMarketLikes = onDocumentCreated(
  "marketPosts/{postId}/likes/{uid}",
  async (event) => {
    await updateMarketCount(event.params.postId, "likesCount", 1, event.id);
    const post = await db.collection("marketPosts").doc(event.params.postId).get();
    const authorUid = post.data()?.authorUid;
    if (authorUid && authorUid !== event.params.uid) {
      await sendMarketActivity(
        authorUid,
        "Someone liked your post.",
        event.params.postId,
        "market_like",
        event.id,
        event.params.uid,
      );
    }
  },
);

exports.removeMarketLikeCount = onDocumentDeleted(
  "marketPosts/{postId}/likes/{uid}",
  (event) => updateMarketCount(event.params.postId, "likesCount", -1, event.id),
);

exports.countMarketComments = onDocumentCreated(
  "marketPosts/{postId}/comments/{commentId}",
  async (event) => {
    await updateMarketCount(event.params.postId, "commentsCount", 1, event.id);
    const comment = event.data?.data();
    const post = await db.collection("marketPosts").doc(event.params.postId).get();
    const authorUid = post.data()?.authorUid;
    if (authorUid && authorUid !== comment?.authorUid) {
      await sendMarketActivity(
        authorUid,
        `${String(comment?.authorName || "Someone")} commented on your post.`,
        event.params.postId,
        "market_comment",
        event.id,
        comment?.authorUid || "",
      );
    }
  },
);

exports.removeMarketCommentCount = onDocumentDeleted(
  "marketPosts/{postId}/comments/{commentId}",
  (event) => updateMarketCount(event.params.postId, "commentsCount", -1, event.id),
);

exports.cleanupMarketCounterEvents = onSchedule(
  "every 24 hours",
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const events = await db
      .collection("marketCounterEvents")
      .where("createdAt", "<", cutoff)
      .limit(400)
      .get();
    if (events.empty) return;
    const batch = db.batch();
    for (const event of events.docs) batch.delete(event.ref);
    await batch.commit();
  },
);

async function refreshMarketFollowCounts(uid) {
  const profile = db.collection("publicProfiles").doc(uid);
  const snapshot = await profile.get();
  if (!snapshot.exists) return;
    const [followers, following] = await Promise.all([
      db.collectionGroup("following").where("followingUid", "==", uid).count().get(),
      db.collectionGroup("following").where("followerUid", "==", uid).count().get(),
  ]);
  await profile.update({
    followersCount: followers.data().count,
    followingCount: following.data().count,
  });
}

exports.countMarketFollowers = onDocumentCreated(
  "marketFollows/{followerUid}/following/{followingUid}",
  async (event) => {
    const data = event.data?.data();
    if (!data?.followerUid || !data?.followingUid) return;
    await Promise.all([
      refreshMarketFollowCounts(data.followerUid),
      refreshMarketFollowCounts(data.followingUid),
    ]);
    if (data.followingUid !== data.followerUid) {
      await sendMarketActivity(
        data.followingUid,
        "You have a new follower.",
        "",
        "market_follow",
        event.id,
        data.followerUid,
      );
    }
  },
);

async function notifyFollowersOfPost(postId, post, idPrefix) {
  const followers = await db
    .collectionGroup("following")
    .where("followingUid", "==", post.authorUid)
    .limit(100)
    .get();
  await Promise.all(
    followers.docs.map((follow) =>
      sendMarketActivity(
        follow.data().followerUid,
        post.type === "status"
          ? `${String(post.authorName || "A user")} shared a new status.`
          : `${String(post.authorName || "A shop")} published a new post.`,
        postId,
        "market_post",
        `${idPrefix}_${follow.id}`,
        post.authorUid,
      ),
    ),
  );
}

exports.notifyMarketFollowers = onDocumentCreated(
  "marketPosts/{postId}",
  async (event) => {
    const post = event.data?.data();
    if (!post?.authorUid) return;
    const publishAt = post.publishAt?.toMillis?.();
    if (publishAt && publishAt > Date.now()) return;
    await notifyFollowersOfPost(event.params.postId, post, event.id);
  },
);

exports.publishScheduledMarketPosts = onSchedule(
  { schedule: "every 15 minutes", timeZone: "Africa/Dar_es_Salaam" },
  async () => {
    const due = await db
      .collection("marketPosts")
      .where("publishAt", "<=", Timestamp.now())
      .limit(100)
      .get();
    for (const doc of due.docs) {
      const post = doc.data();
      if (post.publishNotified === true || post.hidden === true) continue;
      await doc.ref.update({ publishNotified: true });
      await notifyFollowersOfPost(doc.id, post, `sched_${doc.id}`);
    }
  },
);

exports.notifyStatusReply = onDocumentCreated(
  "marketPosts/{postId}/statusReplies/{replyId}",
  async (event) => {
    const reply = event.data?.data();
    if (!reply?.senderUid) return;
    const post = await db.doc(`marketPosts/${event.params.postId}`).get();
    const ownerUid = post.data()?.authorUid;
    if (!ownerUid || ownerUid === reply.senderUid) return;
    const sender = String(reply.senderName || "Someone");
    const content = reply.text ? `: ${String(reply.text).slice(0, 120)}` : "";
    const action = reply.text ? "replied to your status" : `reacted ${reply.emoji} to your status`;
    await sendMarketActivity(
      ownerUid,
      `${sender} ${action}${content}`,
      event.params.postId,
      "market_status_reply",
      event.id,
      reply.senderUid,
    );
  },
);

exports.removeMarketFollowerCount = onDocumentDeleted(
  "marketFollows/{followerUid}/following/{followingUid}",
  async (event) => {
    const data = event.data?.data();
    if (!data?.followerUid || !data?.followingUid) return;
    await Promise.all([
      refreshMarketFollowCounts(data.followerUid),
      refreshMarketFollowCounts(data.followingUid),
    ]);
  },
);

async function sendToTokens(tokens, title, body, data, imageUrl) {
  let success = 0;
  let failure = 0;
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const result = await getMessaging().sendEachForMulticast({
      tokens: chunk,
      notification: imageUrl ? { title, body, imageUrl } : { title, body },
      data,
      android: {
        priority: "high",
        notification: imageUrl
          ? { channelId: "default", imageUrl }
          : { channelId: "default" },
      },
    });
    success += result.successCount;
    failure += result.failureCount;
    // Drop tokens that are no longer valid.
    const stale = [];
    result.responses.forEach((r, idx) => {
      const code = r.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        stale.push(chunk[idx]);
      }
    });
    await Promise.all(
      stale.map((t) => db.collection("deviceTokens").doc(t).delete()),
    );
  }
  return { success, failure };
}

// users/{businessUid}/notifications/{id} -> push to the business owner's devices.
exports.pushStaffActivity = onDocumentCreated(
  "users/{businessUid}/notifications/{id}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const snap = await db
      .collection("deviceTokens")
      .where("uid", "==", event.params.businessUid)
      .get();
    const tokens = snap.docs.map((d) => d.id);
    if (!tokens.length) return;
    await sendToTokens(tokens, String(data.actorName || "Staff"), String(data.summary || ""), {
      type: "activity",
    });
  },
);

exports.notifyBusinessMarketVerified = onDocumentWritten(
  "marketBusinessVerifications/{businessUid}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after || after.verified !== true || before?.verified === true) return;

    const { businessUid } = event.params;
    const profile = await db
      .doc(`users/${businessUid}/profile/company`)
      .get();
    const isSwahili = String(profile.data()?.language || "")
      .toLowerCase()
      .startsWith("sw");
    await db.collection("users").doc(businessUid).collection("notifications").add({
      actorUid: "system",
      actorName: "MJASI",
      action: "verification",
      summary: isSwahili
        ? "Biashara yako imethibitishwa na MJASI."
        : "Your business has been verified by MJASI.",
      createdAt: FieldValue.serverTimestamp(),
      read: false,
    });
  },
);

// Writes an in-app inbox item and pushes to the user's devices.
async function notifyUser(uid, body, taskId, kind) {
  await db.collection("userNotifications").doc(uid).collection("items").add({
    body,
    taskId,
    kind,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  const snap = await db.collection("deviceTokens").where("uid", "==", uid).get();
  const tokens = snap.docs.map((d) => d.id);
  if (tokens.length) {
    await sendToTokens(tokens, "Kazi", body, { type: "task", taskId });
  }
}

// Task changes -> push to the assignee, or notify the owner via the activity feed.
exports.pushTaskChanges = onDocumentWritten(
  "users/{businessUid}/tasks/{taskId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;
    const { businessUid } = event.params;
    const title = String(after.title || "Task");

    let toAssignee = null;
    let toOwner = null;
    if (!before) {
      toAssignee = `Kazi mpya: ${title}`;
    } else if (before.status !== after.status) {
      if (after.status === "returned") toAssignee = `Kazi imerudishwa: ${title}`;
      else if (after.status === "approved") toAssignee = `Kazi imeidhinishwa: ${title}`;
      else if (after.status === "cancelled") toAssignee = `Kazi imeghairiwa: ${title}`;
      else if (after.status === "inProgress" && before.status === "assigned")
        toOwner = `Ameanza kazi: ${title}`;
      else if (after.status === "submitted") {
        const amt = after.collectedAmount;
        toOwner = `Amewasilisha kazi: ${title}` +
          (typeof amt === "number" ? ` (TZS ${amt})` : "");
      }
    } else if (
      before.dueDate?.toMillis?.() !== after.dueDate?.toMillis?.() &&
      after.status !== "approved" && after.status !== "cancelled"
    ) {
      toAssignee = `Muda wa kazi umebadilishwa: ${title}`;
    }

    if (toAssignee && after.assigneeUid) {
      await notifyUser(after.assigneeUid, toAssignee, event.params.taskId, "task");
    }
    if (toOwner) {
      // pushStaffActivity delivers this to the owner's devices.
      await db.collection("users").doc(businessUid).collection("notifications").add({
        actorUid: after.assigneeUid || "",
        actorName: String(after.assigneeName || "Staff"),
        action: "task",
        taskId: event.params.taskId,
        summary: toOwner,
        createdAt: FieldValue.serverTimestamp(),
        read: false,
      });
    }
  },
);

// Hourly: remind assignees (and the owner) about tasks past their deadline, once per deadline.
exports.notifyOverdueTasks = onSchedule("every 60 minutes", async () => {
  const now = Date.now();
  const snap = await db
    .collectionGroup("tasks")
    .where("dueDate", "<", Timestamp.fromMillis(now))
    .where("dueDate", ">", Timestamp.fromMillis(now - 14 * 24 * 3600 * 1000))
    .limit(500)
    .get();
  for (const doc of snap.docs) {
    const t = doc.data();
    if (!["assigned", "inProgress", "returned"].includes(t.status)) continue;
    const due = t.dueDate.toMillis();
    if (t.overdueNotifiedFor === due) continue;
    await doc.ref.update({ overdueNotifiedFor: due });
    const title = String(t.title || "Task");
    if (t.assigneeUid) {
      await notifyUser(t.assigneeUid, `Kazi imechelewa: ${title}`, doc.id, "overdue");
    }
    const businessUid = doc.ref.parent.parent.id;
    await db.collection("users").doc(businessUid).collection("notifications").add({
      actorUid: t.assigneeUid || "",
      actorName: String(t.assigneeName || "Staff"),
      action: "task",
      taskId: doc.id,
      summary: `Kazi imechelewa: ${title}`,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
    });
  }
});

// Super Admin announcement -> push to every registered device.
exports.pushAnnouncement = onDocumentCreated("announcements/{id}", async (event) => {
  const data = event.data?.data();
  if (!data) return;
  const snap = await db.collection("deviceTokens").get();
  const tokens = snap.docs.map((d) => d.id);
  if (!tokens.length) {
    await event.data.ref.update({ sentCount: 0, failureCount: 0 });
    return;
  }
  const { success, failure } = await sendToTokens(
    tokens,
    String(data.title || "Mjasi POS"),
    String(data.body || ""),
    { type: "announcement" },
    data.imageUrl || undefined,
  );
  await event.data.ref.update({ sentCount: success, failureCount: failure });
});

exports.deleteMyAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to delete your account.");
  }
  if (request.data?.confirm !== "DELETE") {
    throw new HttpsError("invalid-argument", "Deletion was not confirmed.");
  }
  // Require a fresh sign-in so a stolen session cannot delete the account.
  const authTime = request.auth.token.auth_time ?? 0;
  if (Date.now() / 1000 - authTime > 5 * 60) {
    throw new HttpsError(
      "failed-precondition",
      "Please sign in again before deleting your account.",
    );
  }

  const membershipRef = db.collection("employeeMemberships").doc(uid);
  const membership = await membershipRef.get();
  const modernMemberships = await db
    .collectionGroup("members")
    .where("employeeUid", "==", uid)
    .get();
  const modernOwnerships = modernMemberships.docs.filter(
    (doc) => doc.data().role === "owner" && doc.data().active === true,
  );
  if (modernOwnerships.length > 0) {
    throw new HttpsError(
      "failed-precondition",
      "Transfer or close businesses you own before deleting this account.",
    );
  }

  // A staff member only removes their own access; the business data stays.
  if (membership.exists) {
    await membershipRef.delete();
    await Promise.all(modernMemberships.docs.map((doc) => doc.ref.delete()));
    await getAuth().deleteUser(uid);
    return { success: true, role: "staff" };
  }

  const company = await db.doc(`users/${uid}/profile/company`).get();
  const role = String(company.data()?.role ?? "").toLowerCase();
  if (["superadmin", "super_admin", "super-admin", "super admin"].includes(role)) {
    throw new HttpsError(
      "permission-denied",
      "Administrator accounts cannot be deleted here.",
    );
  }

  if (!company.exists) {
    await Promise.all(modernMemberships.docs.map((doc) => doc.ref.delete()));
    await db.recursiveDelete(db.doc(`personalUsers/${uid}`));
    await db.recursiveDelete(db.doc(`subscriptions/${uid}`));
    await db.recursiveDelete(db.doc(`accountAccess/${uid}`));
    await getAuth().deleteUser(uid);
    return {
      success: true,
      role: modernMemberships.size > 0 ? "staff" : "personal",
    };
  }

  // Business owner: remove staff logins, business data, files, then the login.
  const staffSnap = await db
    .collection("employeeMemberships")
    .where("businessUid", "==", uid)
    .get();
  for (const staffDoc of staffSnap.docs) {
    try {
      await getAuth().deleteUser(staffDoc.id);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
    await staffDoc.ref.delete();
  }

  const receipts = await db
    .collection("receipts")
    .where("businessUid", "==", uid)
    .get();
  for (const receipt of receipts.docs) {
    await db.recursiveDelete(receipt.ref);
  }

  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.recursiveDelete(db.doc(`personalUsers/${uid}`));
  await db.recursiveDelete(db.doc(`subscriptions/${uid}`));
  await db.recursiveDelete(db.doc(`accountAccess/${uid}`));
  await getStorage().bucket().deleteFiles({ prefix: `users/${uid}/` });
  await Promise.all(modernMemberships.docs.map((doc) => doc.ref.delete()));
  await getAuth().deleteUser(uid);

  return { success: true, role: "owner" };
});

exports.updateStaffPassword = onCall(async (request) => {
  const ownerUid = request.auth?.uid;
  if (!ownerUid) {
    throw new HttpsError("unauthenticated", "Sign in to change staff passwords.");
  }

  const { employeeUid, newPassword } = request.data ?? {};
  if (typeof employeeUid !== "string" || employeeUid.length === 0) {
    throw new HttpsError("invalid-argument", "A staff account is required.");
  }
  if (employeeUid === ownerUid) {
    throw new HttpsError(
      "permission-denied",
      "Business owners cannot change their own password here.",
    );
  }
  if (typeof newPassword !== "string" || newPassword.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "The password must be at least 6 characters.",
    );
  }

  const ownerMembershipRef = db.collection("employeeMemberships").doc(ownerUid);
  const staffMembershipRef = db
    .collection("employeeMemberships")
    .doc(employeeUid);
  const accessRef = db.collection("accountAccess").doc(ownerUid);
  const [ownerMembership, staffMembership, accountAccess] = await Promise.all([
    ownerMembershipRef.get(),
    staffMembershipRef.get(),
    accessRef.get(),
  ]);

  if (ownerMembership.exists) {
    throw new HttpsError(
      "permission-denied",
      "Only the business owner can change staff passwords.",
    );
  }
  if (accountAccess.data()?.disabled === true) {
    throw new HttpsError(
      "permission-denied",
      "This business account is disabled.",
    );
  }

  const staffData = staffMembership.data();
  if (!staffMembership.exists || staffData.businessUid !== ownerUid) {
    throw new HttpsError(
      "not-found",
      "The staff account does not belong to this business.",
    );
  }

  let businessEmail =
    typeof staffData.businessEmail === "string"
      ? staffData.businessEmail.trim().toLowerCase()
      : "";
  if (!businessEmail) {
    const owner = await getAuth().getUser(ownerUid);
    businessEmail = owner.email?.trim().toLowerCase() ?? "";
  }
  if (!businessEmail) {
    throw new HttpsError(
      "failed-precondition",
      "The business owner account must have an email address.",
    );
  }

  const digest = createHash("sha256")
    .update(`${businessEmail}|${newPassword}`, "utf8")
    .digest("hex");
  const staffAuthEmail = `staff.${digest}@staff.tra-list.invalid`;

  await getAuth().updateUser(employeeUid, {
    email: staffAuthEmail,
    password: newPassword,
  });

  return { success: true };
});

function normalizePermissions(value) {
  const modules = [
    "transactions",
    "invoices",
    "receipts",
    "quotations",
    "jobs",
    "tasks",
    "analytics",
    "categories",
    "stock",
    "profile",
  ];
  const actions = ["view", "create", "edit", "delete"];
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const permissions = {};
  for (const module of modules) {
    const modulePermissions = value[module];
    if (!modulePermissions || typeof modulePermissions !== "object" ||
        Array.isArray(modulePermissions)) return null;
    permissions[module] = {};
    for (const action of actions) {
      if (typeof modulePermissions[action] !== "boolean") return null;
      permissions[module][action] = modulePermissions[action];
    }
  }
  return permissions;
}

async function assertBusinessOwner(uid, businessUid) {
  const access = await db.collection("accountAccess").doc(uid).get();
  if (access.data()?.disabled === true) {
    throw new HttpsError("permission-denied", "This account is disabled.");
  }
  const businessAccess = await db
    .collection("accountAccess")
    .doc(businessUid)
    .get();
  if (businessAccess.data()?.disabled === true) {
    throw new HttpsError("permission-denied", "This business is disabled.");
  }

  if (businessUid === uid) {
    const [profile, legacyMembership, ownMembership] = await Promise.all([
      db.doc(`users/${businessUid}/profile/company`).get(),
      db.collection("employeeMemberships").doc(uid).get(),
      db.doc(`businessMemberships/${businessUid}/members/${uid}`).get(),
    ]);
    if (
      profile.exists &&
      (!legacyMembership.exists ||
        legacyMembership.data()?.businessUid !== businessUid)
    ) {
      if (!ownMembership.exists) return;
      if (
        ownMembership.data()?.role === "owner" &&
        ownMembership.data()?.active === true
      ) {
        return;
      }
    }
  }

  const membership = await db
    .doc(`businessMemberships/${businessUid}/members/${uid}`)
    .get();
  if (
    membership.data()?.role !== "owner" ||
    membership.data()?.active !== true ||
    membership.data()?.businessUid !== businessUid
  ) {
    throw new HttpsError(
      "permission-denied",
      "Only an authorized business owner can perform this action.",
    );
  }
}

exports.createBusiness = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to create a business.");
  }
  const access = await db.collection("accountAccess").doc(uid).get();
  if (access.data()?.disabled === true) {
    throw new HttpsError("permission-denied", "This account is disabled.");
  }

  const name = typeof request.data?.name === "string"
    ? request.data.name.trim()
    : "";
  const phone = typeof request.data?.phone === "string"
    ? request.data.phone.trim()
    : "";
  if (!name || name.length > 120 || phone.length > 40) {
    throw new HttpsError("invalid-argument", "Enter a valid business profile.");
  }

  const legacyMembership = await db.collection("employeeMemberships").doc(uid).get();
  if (legacyMembership.exists) {
    throw new HttpsError(
      "failed-precondition",
      "Staff accounts cannot create a business profile.",
    );
  }
  const businessUid = uid;
  const businessName = name;
  const user = await getAuth().getUser(uid);
  const profileRef = db.doc(`users/${businessUid}/profile/company`);
  const memberRef = db.doc(
    `businessMemberships/${businessUid}/members/${uid}`,
  );
  const profile = {
    name: businessName,
    shopNickname: "",
    ownerName: user.displayName?.trim() ?? "",
    email: user.email ?? "",
    phone,
    address: "",
    website: "",
    taxId: "",
    role: "user",
    handle: "",
    logoUrl: "",
    logoSource: "firebase",
    language: "en",
    beneficiary: "",
    bank: "",
    account: "",
    swift: "",
    paymentMethod: "Bank Transfer",
    colors: {
      brand: 0xFFF15A24,
      footer: 0xFF424242,
      accent: 0xFF1976D2,
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  const membership = {
    employeeUid: uid,
    businessUid,
    businessName,
    businessEmail: user.email ?? "",
    shopNickname: "",
    name: user.displayName?.trim() ?? "",
    email: user.email ?? "",
    phone: "",
    active: true,
    role: "owner",
    permissions: {},
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  await db.runTransaction(async (transaction) => {
    const [existingProfile, existingMembership] = await Promise.all([
      transaction.get(profileRef),
      transaction.get(memberRef),
    ]);
    if (existingProfile.exists || existingMembership.exists) {
      throw new HttpsError(
        "already-exists",
        "This account already has a business profile.",
      );
    }
    transaction.create(profileRef, profile);
    transaction.create(memberRef, membership);
  });
  return { businessUid, businessName };
});

exports.createBusinessInvitation = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to invite a member.");
  }
  const businessUid = request.data?.businessUid;
  if (typeof businessUid !== "string" || !businessUid) {
    throw new HttpsError("invalid-argument", "A business is required.");
  }
  await assertBusinessOwner(uid, businessUid);

  const email = typeof request.data?.email === "string"
    ? request.data.email.trim().toLowerCase()
    : "";
  const name = typeof request.data?.name === "string"
    ? request.data.name.trim()
    : "";
  const shopNickname = typeof request.data?.shopNickname === "string"
    ? request.data.shopNickname.trim()
    : "";
  const phone = typeof request.data?.phone === "string"
    ? request.data.phone.trim()
    : "";
  const permissions = normalizePermissions(request.data?.permissions);
  if (
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
    email.length > 254 ||
    !name ||
    name.length > 100 ||
    !shopNickname ||
    shopNickname.length > 80 ||
    phone.length > 40 ||
    !permissions
  ) {
    throw new HttpsError("invalid-argument", "Enter valid invitation details.");
  }

  const profile = await db
    .doc(`users/${businessUid}/profile/company`)
    .get();
  const businessName = profile.data()?.name?.toString().trim() ?? "";
  if (!businessName) {
    throw new HttpsError("failed-precondition", "The business profile is missing.");
  }

  const code = randomBytes(18).toString("hex");
  await db.collection("businessInvitations").doc(code).create({
    businessUid,
    businessName,
    email,
    name,
    phone,
    shopNickname,
    permissions,
    status: "pending",
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + 14 * 24 * 60 * 60 * 1000),
  });
  return { code };
});

exports.claimBusinessInvitation = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to join a business.");
  }
  const access = await db.collection("accountAccess").doc(uid).get();
  if (access.data()?.disabled === true) {
    throw new HttpsError("permission-denied", "This account is disabled.");
  }
  const code = typeof request.data?.code === "string"
    ? request.data.code.trim().toLowerCase()
    : "";
  const email = request.auth.token.email?.trim().toLowerCase() ?? "";
  if (request.auth.token.email_verified !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Verify your email address before accepting a business invitation.",
    );
  }
  if (!/^[a-f0-9]{36}$/.test(code) || !email) {
    throw new HttpsError("invalid-argument", "Enter a valid invitation code.");
  }

  const invitationRef = db.collection("businessInvitations").doc(code);
  const invitation = await invitationRef.get();
  const data = invitation.data();
  if (
    !data ||
    data.status !== "pending" ||
    data.email !== email ||
    !(data.expiresAt instanceof Timestamp) ||
    data.expiresAt.toMillis() <= Date.now()
  ) {
    throw new HttpsError(
      "permission-denied",
      "This invitation is invalid, expired, or assigned to another email.",
    );
  }

  const businessUid = data.businessUid;
  const businessAccess = await db
    .collection("accountAccess")
    .doc(businessUid)
    .get();
  const businessProfileRef = db.doc(
    `users/${businessUid}/profile/company`,
  );
  if (businessAccess.data()?.disabled === true) {
    throw new HttpsError("failed-precondition", "This business is disabled.");
  }
  const membershipRef = db.doc(
    `businessMemberships/${businessUid}/members/${uid}`,
  );
  await db.runTransaction(async (transaction) => {
    const [currentInvitation, existingMembership, businessProfile] = await Promise.all([
      transaction.get(invitationRef),
      transaction.get(membershipRef),
      transaction.get(businessProfileRef),
    ]);
    const current = currentInvitation.data();
    if (
      !current ||
      current.status !== "pending" ||
      current.email !== email ||
      !(current.expiresAt instanceof Timestamp) ||
      current.expiresAt.toMillis() <= Date.now()
    ) {
      throw new HttpsError("failed-precondition", "The invitation is no longer available.");
    }
    if (!businessProfile.exists) {
      throw new HttpsError("failed-precondition", "This business is no longer available.");
    }
    if (existingMembership.exists) {
      throw new HttpsError("already-exists", "This account already belongs to this business.");
    }

    transaction.create(membershipRef, {
      employeeUid: uid,
      businessUid,
      businessName: current.businessName,
      businessEmail: "",
      shopNickname: current.shopNickname,
      name: current.name,
      email,
      phone: current.phone,
      active: true,
      role: "staff",
      permissions: current.permissions,
      createdBy: current.createdBy,
      invitationId: code,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(invitationRef, {
      status: "accepted",
      acceptedBy: uid,
      acceptedAt: FieldValue.serverTimestamp(),
    });
  });
  return { businessUid, businessName: data.businessName };
});
