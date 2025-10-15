import 'package:flutter/material.dart';
import 'job_model.dart'; // Adjust path as needed
import 'add_job_screen.dart'; // Adjust path as needed

class JobListScreen extends StatefulWidget {
  const JobListScreen({Key? key}) : super(key: key);

  @override
  _JobListScreenState createState() => _JobListScreenState();
}

class _JobListScreenState extends State<JobListScreen> {
  // Dummy data - replace with data from your database or state management
  final List<Job> _jobs = [
    Job(
      id: '1',
      customerName:
          'Asha Juma', // This should be clientName if using the other model
      jobType: 'Website Design',
      customerPhone: '0712345678',
      totalCost: 1500000,
      advancePaid: 700000,
      startDate: DateTime.now().subtract(Duration(days: 5)),
      dueDate: DateTime.now().add(Duration(hours: 20)),
      isImportant: true,
    ),
    Job(
      id: '2',
      customerName:
          'John Doe', // This should be clientName if using the other model
      jobType: 'Logo Branding',
      customerPhone: '0755112233',
      totalCost: 500000,
      advancePaid: 500000,
      startDate: DateTime.now().subtract(Duration(days: 10)),
      dueDate: DateTime.now().subtract(Duration(days: 2)),
      status: JobStatus.Completed,
    ),
    Job(
      id: '3',
      customerName:
          'Fatuma Said', // This should be clientName if using the other model
      jobType: 'Mobile App',
      customerPhone: '0688990011',
      totalCost: 3000000,
      startDate: DateTime.now().subtract(Duration(days: 2)),
      dueDate: DateTime.now().add(Duration(days: 15)),
    ),
  ];

  // State for filtering
  String _filter = 'All'; // 'All', 'Completed', 'Important'

  List<Job> get _filteredJobs {
    if (_filter == 'Completed') {
      return _jobs.where((job) => job.status == JobStatus.Completed).toList();
    }
    if (_filter == 'Important') {
      return _jobs.where((job) => job.isImportant).toList();
    }
    return _jobs;
  }

  String _formatRemainingTime(Duration duration) {
    if (duration.isNegative || duration.inSeconds == 0) {
      return "Imechelewa";
    }
    if (duration.inDays > 0) {
      return 'Siku ${duration.inDays}';
    } else if (duration.inHours > 0) {
      return 'Masaa ${duration.inHours}';
    } else {
      return 'Dakika ${duration.inMinutes}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Orodha ya Kazi'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _filter = value),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'All',
                child: Text('Kazi Zote'),
              ),
              const PopupMenuItem<String>(
                value: 'Important',
                child: Text('Kazi za Muhimu'),
              ),
              const PopupMenuItem<String>(
                value: 'Completed',
                child: Text('Zilizokamilika'),
              ),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _filteredJobs.length,
        itemBuilder: (context, index) {
          final job = _filteredJobs[index];
          final remainingTime = job.remainingTime;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: job.isDueSoon
                ? Colors.red.shade50
                : (job.status == JobStatus.Completed
                      ? Colors.green.shade50
                      : null),
            child: ListTile(
              title: Text(
                job.jobType,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(job.customerName),
              leading: IconButton(
                icon: Icon(
                  job.isImportant ? Icons.star : Icons.star_border,
                  color: job.isImportant ? Colors.amber : Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    job.isImportant = !job.isImportant;
                  });
                },
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Tsh ${job.totalCost.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  if (job.status != JobStatus.Completed)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (job.isDueSoon)
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red.shade700,
                            size: 16,
                          ),
                        if (job.isDueSoon) SizedBox(width: 4),
                        Text(
                          _formatRemainingTime(remainingTime),
                          style: TextStyle(
                            color: job.isDueSoon
                                ? Colors.red.shade700
                                : Colors.blueGrey,
                            fontSize: 12,
                            fontWeight: job.isDueSoon
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    )
                  else
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                ],
              ),
              onTap: () {
                // TODO: Navigate to a Job Details screen
                print('Tapped on job: ${job.id}');
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => AddJobScreen()));
        },
        child: Icon(Icons.add),
        tooltip: 'Sajili Kazi Mpya',
      ),
    );
  }
}
