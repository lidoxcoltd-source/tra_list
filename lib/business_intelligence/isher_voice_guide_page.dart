import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class IsherVoiceGuidePage extends StatelessWidget {
  const IsherVoiceGuidePage({super.key});

  static const _cyan = Color(0xFF61E6F2);
  static const _muted = Color(0xFFB8C5D8);

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('isher_guide_copied'.tr)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080817),
    appBar: AppBar(
      backgroundColor: const Color(0xFF080817),
      foregroundColor: Colors.white,
      title: Text('isher_guide_title'.tr),
    ),
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF080817), Color(0xFF101127), Color(0xFF111C2B)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _hero(),
                const SizedBox(height: 28),
                _sectionTitle('isher_guide_capabilities_title'.tr, '01'),
                const SizedBox(height: 12),
                _capability(
                  Icons.query_stats_rounded,
                  'isher_guide_reports_title'.tr,
                  'isher_guide_reports_body'.tr,
                ),
                _capability(
                  Icons.inventory_2_outlined,
                  'isher_guide_products_title'.tr,
                  'isher_guide_products_body'.tr,
                ),
                _capability(
                  Icons.receipt_long_outlined,
                  'isher_guide_customers_title'.tr,
                  'isher_guide_customers_body'.tr,
                ),
                _capability(
                  Icons.travel_explore_rounded,
                  'isher_guide_research_title'.tr,
                  'isher_guide_research_body'.tr,
                ),
                const SizedBox(height: 28),
                _sectionTitle('isher_guide_questions_title'.tr, '02'),
                const SizedBox(height: 12),
                _example(
                  'isher_guide_question_report'.tr,
                  'Nipe muhtasari wa biashara yangu wa mwezi huu.',
                  context,
                ),
                _example(
                  'isher_guide_question_stock'.tr,
                  'Ni bidhaa gani zina stock ndogo na bei zake ni zipi?',
                  context,
                ),
                _example(
                  'isher_guide_question_customer'.tr,
                  'Nionyeshe invoices za hivi karibuni za wateja.',
                  context,
                ),
                _example(
                  'isher_guide_question_research'.tr,
                  'Tafuta biashara zinazofanana na yangu mtandaoni.',
                  context,
                ),
                const SizedBox(height: 28),
                _sectionTitle('isher_guide_important_title'.tr, '03'),
                const SizedBox(height: 12),
                _important('isher_guide_dates'.tr),
                _important('isher_guide_categories'.tr),
                _important('isher_guide_review'.tr),
                _important('isher_guide_privacy'.tr),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF10192A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _cyan.withValues(alpha: 0.28)),
      boxShadow: [
        BoxShadow(
          color: _cyan.withValues(alpha: 0.08),
          blurRadius: 28,
          spreadRadius: 1,
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _cyan.withValues(alpha: 0.12),
            border: Border.all(color: _cyan.withValues(alpha: 0.4)),
          ),
          child: const Icon(Icons.graphic_eq_rounded, color: _cyan),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ISHER AI  /  VOICE GUIDE',
                style: TextStyle(
                  color: _cyan.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'isher_guide_intro'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String title, String number) => Row(
    children: [
      Text(
        number,
        style: const TextStyle(
          color: _cyan,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(child: Divider(color: Color(0xFF34445A), height: 1)),
    ],
  );

  Widget _capability(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: _cyan),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _example(String label, String example, BuildContext context) =>
      Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
        decoration: BoxDecoration(
          color: const Color(0xFF151B2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF29394B)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '“$example”',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'isher_guide_copy'.tr,
              onPressed: () => _copy(context, example),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
          ],
        ),
      );

  Widget _important(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 6, color: _cyan),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
          ),
        ),
      ],
    ),
  );
}
