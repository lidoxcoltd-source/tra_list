import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add 'intl' to your pubspec.yaml

class AddJobScreen extends StatefulWidget {
  const AddJobScreen({Key? key}) : super(key: key);

  @override
  _AddJobScreenState createState() => _AddJobScreenState();
}

class _AddJobScreenState extends State<AddJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _jobTypeController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _totalCostController = TextEditingController();
  final _advancePaidController = TextEditingController();

  DateTime? _startDate;
  DateTime? _dueDate;

  @override
  void dispose() {
    _customerNameController.dispose();
    _jobTypeController.dispose();
    _customerPhoneController.dispose();
    _totalCostController.dispose();
    _advancePaidController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _dueDate = picked;
        }
      });
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      // Here you would typically use a state management solution (like GetX, Provider, Riverpod)
      // to create a new Job object and save it.
      print('Form is valid. Saving job...');
      print('Customer: ${_customerNameController.text}');
      print('Job Type: ${_jobTypeController.text}');
      // ... and so on for other fields.

      // After saving, you can navigate back.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sajili Kazi Mpya')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _customerNameController,
                decoration: InputDecoration(labelText: 'Jina la Mteja'),
                validator: (value) =>
                    value!.isEmpty ? 'Jina linahitajika' : null,
              ),
              TextFormField(
                controller: _jobTypeController,
                decoration: InputDecoration(labelText: 'Aina ya Kazi'),
                validator: (value) =>
                    value!.isEmpty ? 'Aina ya kazi inahitajika' : null,
              ),
              TextFormField(
                controller: _customerPhoneController,
                decoration: InputDecoration(labelText: 'Namba ya Simu'),
                keyboardType: TextInputType.phone,
                validator: (value) =>
                    value!.isEmpty ? 'Namba ya simu inahitajika' : null,
              ),
              TextFormField(
                controller: _totalCostController,
                decoration: InputDecoration(
                  labelText: 'Malipo ya Kazi (Jumla)',
                ),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value!.isEmpty ? 'Malipo yanahitajika' : null,
              ),
              TextFormField(
                controller: _advancePaidController,
                decoration: InputDecoration(labelText: 'Advance Iliyolipwa'),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _startDate == null
                          ? 'Chagua Tarehe ya Kuanza'
                          : 'Kuanza: ${DateFormat.yMd().format(_startDate!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _selectDate(context, true),
                    child: Text('Chagua'),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dueDate == null
                          ? 'Chagua Tarehe ya Kukamilika'
                          : 'Kukamilika: ${DateFormat.yMd().format(_dueDate!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _selectDate(context, false),
                    child: Text('Chagua'),
                  ),
                ],
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submitForm,
                child: Text('SAJILI KAZI'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
