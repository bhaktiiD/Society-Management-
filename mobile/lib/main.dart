import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

void main() {
  runApp(const SocietyOSApp());
}

class SocietyOSApp extends StatelessWidget {
  const SocietyOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SocietyOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));

  bool isLoading = true;
  String message = 'Connecting to backend...';

  @override
  void initState() {
    super.initState();
    checkBackend();
  }

  Future<void> checkBackend() async {
    setState(() {
      isLoading = true;
      message = 'Connecting to backend...';
    });

    try {
      final response = await dio.get('/health');

      if (!mounted) return;

      setState(() {
        message =
            'Status: ${response.data['status']}\n'
            'Service: ${response.data['service']}';
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Connection failed:\n$error';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SocietyOS'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.apartment, size: 70, color: Colors.teal),
              const SizedBox(height: 20),
              const Text(
                'SocietyOS Backend Connection',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (isLoading) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isLoading ? null : checkBackend,
                child: const Text('Check Connection Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
