import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' as pdf; 
import 'package:pdf/widgets.dart' as pw; 
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'FaceVerificationScreen.dart';

class ResultScreen extends StatelessWidget {
  final List<File> uploadedImages;
  final List<Map<String, dynamic>> verificationResults;

  const ResultScreen({super.key, required this.uploadedImages, required this.verificationResults});

  Future<bool?> _showResetConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          'Reset Confirmation',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to reset all verification results and uploaded images?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _resetApp(BuildContext context) async {
    final bool? confirm = await _showResetConfirmationDialog(context);
    if (confirm == true) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const FaceVerificationScreen()),
            (route) => false,
      );
    }
  }

  Future<void> _shareAsPdf(BuildContext context) async {
    try {
      if (verificationResults.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No results to share')),
        );
        return;
      }

      print('Starting PDF generation...');
      final pdfDoc = pw.Document(); 

      print('Document created, adding pages...');
      for (var result in verificationResults) {
        final uploadedImageBytes = await File(result['uploadedImage'].path).readAsBytes();
        final capturedImageBytes = await File(result['capturedImage'].path).readAsBytes();

        final uploadedImage = pw.MemoryImage(uploadedImageBytes);
        final capturedImage = pw.MemoryImage(capturedImageBytes);

        pdfDoc.addPage(
          pw.Page(
            build: (pw.Context context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Uploaded Image:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Image(uploadedImage, height: 200, fit: pw.BoxFit.cover),
                pw.SizedBox(height: 20),
                pw.Text('Captured Image:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Image(capturedImage, height: 200, fit: pw.BoxFit.cover),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Result:',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  result['details'],
                  style: pw.TextStyle(
                    fontSize: 14,
                    color: result['isVerified'] ? pdf.PdfColors.green : pdf.PdfColors.red,
                  ),
                ),
                pw.SizedBox(height: 40),
              ],
            ),
          ),
        );
      }

      print('Pages added, saving PDF...');
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/verification_results.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdfDoc.save());

      if (!await file.exists()) {
        throw Exception('PDF file was not created at $filePath');
      }
      print('PDF saved successfully at: $filePath');

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Face Verification Results',
      );
      print('Share dialog triggered');
    } catch (e) {
      print('Error during PDF sharing: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Verification Results',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF3F51B5),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: 'Share as PDF',
            onPressed: () => _shareAsPdf(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Reset',
            onPressed: () => _resetApp(context),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...verificationResults.map((result) => Column(
                children: [
                  Card(
                    elevation: 5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.file(result['uploadedImage'], height: 200, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.file(result['capturedImage'], height: 200, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        result['details'],
                        style: TextStyle(
                          fontSize: 16,
                          color: result['isVerified'] ? Colors.green : Colors.redAccent,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }
}
