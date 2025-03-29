import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'dart:io';
import 'ResultScreen.dart';

class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key});

  @override
  _FaceVerificationScreenState createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  List<File> _uploadedImages = [];
  File? _capturedImage;
  final ImagePicker _picker = ImagePicker();
  int _currentImageIndex = 0;
  List<Map<String, dynamic>> verificationResults = [];
  final faceDetector = GoogleMlKit.vision.faceDetector(
    FaceDetectorOptions(enableLandmarks: true, performanceMode: FaceDetectorMode.accurate),
  );
  bool _isVerifying = false; // Added for loading animation

  Future<void> _pickImagesFromGallery() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _uploadedImages = images.map((image) => File(image.path)).toList();
        _currentImageIndex = 0;
        _capturedImage = null;
        verificationResults.clear();
      });
    }
  }

  Future<void> _captureImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _capturedImage = File(image.path);
      });
    }
  }

  Future<void> _verifyFaces() async {
    if (_uploadedImages.isEmpty || _capturedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload images and capture an image')),
      );
      return;
    }

    setState(() {
      _isVerifying = true; // Start loading animation
    });

    try {
      final faces1 = await _detectFaces(_uploadedImages[_currentImageIndex]);
      final faces2 = await _detectFaces(_capturedImage!);

      if (faces1.isEmpty || faces2.isEmpty) {
        _addResult('No face detected in one or both images.', 0.0, false);
        bool? proceed = await _showVerificationDialog(false, 'No face detected', showOptions: true);
        if (proceed == true) {
          _moveToNextOrResult();
        }
      } else if (faces1.length > 1 || faces2.length > 1) {
        _addResult('Multiple faces detected. Please use images with one face.', 0.0, false);
        bool? proceed = await _showVerificationDialog(false, 'Multiple faces detected', showOptions: true);
        if (proceed == true) {
          _moveToNextOrResult();
        }
      } else {
        final comparisonResult = _compareFaces(faces1[0], faces2[0]);
        double matchPercentage = comparisonResult['percentage'];
        String details = comparisonResult['details'];
        const double threshold = 60.0;
        bool isVerified = matchPercentage >= threshold;
        _addResult(
          'Image ${_currentImageIndex + 1}: ${isVerified ? 'Match Found' : 'No Match'}\nConfidence: ${matchPercentage.toStringAsFixed(1)}%\n$details',
          matchPercentage,
          isVerified,
        );
        await _showVerificationDialog(isVerified, 'Confidence: ${matchPercentage.toStringAsFixed(1)}%');
        _moveToNextOrResult();
      }
    } catch (e) {
      _addResult('Error verifying faces: $e', 0.0, false);
      await _showVerificationDialog(false, 'Error: $e');
      _moveToNextOrResult();
    } finally {
      setState(() {
        _isVerifying = false; // Stop loading animation
      });
    }
  }

  void _moveToNextOrResult() {
    if (_currentImageIndex + 1 >= _uploadedImages.length) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            uploadedImages: _uploadedImages,
            verificationResults: verificationResults,
          ),
        ),
      );
    } else {
      setState(() {
        _currentImageIndex++;
        _capturedImage = null;
      });
    }
  }

  Future<bool?> _showVerificationDialog(bool isVerified, String message, {bool showOptions = false}) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          isVerified ? 'Image Verified' : 'Image Not Verified',
          style: TextStyle(
            color: isVerified ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 16),
        ),
        actions: showOptions
            ? [
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Skip', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () {
              _addResult(
                'Image ${_currentImageIndex + 1}: Absent\n$message',
                0.0,
                false,
              );
              Navigator.pop(context, true);
            },
            child: const Text('Absent', style: TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Try Again', style: TextStyle(color: Colors.blue)),
          ),
        ]
            : [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _addResult(String result, double confidence, bool isVerified) {
    verificationResults.add({
      'uploadedImage': _uploadedImages[_currentImageIndex],
      'capturedImage': _capturedImage!,
      'isVerified': isVerified,
      'confidence': confidence,
      'details': result,
    });
  }

  void _navigateToResultScreen() {
    if (verificationResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No verification results available yet')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultScreen(
          uploadedImages: _uploadedImages,
          verificationResults: verificationResults,
        ),
      ),
    );
  }

  File _preprocessImage(File imageFile) {
    img.Image? image = img.decodeImage(imageFile.readAsBytesSync());
    if (image == null) return imageFile;
    img.Image resizedImage = img.copyResize(image, width: 300, height: 300);
    const double contrastFactor = 1.2;
    img.Image adjustedImage = _manualAdjustContrast(resizedImage, contrastFactor);
    File tempFile = File('${imageFile.path}_preprocessed.jpg')..writeAsBytesSync(img.encodeJpg(adjustedImage));
    return tempFile;
  }

  img.Image _manualAdjustContrast(img.Image image, double contrastFactor) {
    double mean = 0;
    int pixelCount = image.width * image.height;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        var pixel = image.getPixel(x, y);
        double brightness = (pixel.r + pixel.g + pixel.b) / 3;
        mean += brightness;
      }
    }
    mean /= pixelCount;
    img.Image adjustedImage = img.Image.from(image);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        var pixel = image.getPixel(x, y);
        num r = ((pixel.r - mean) * contrastFactor + mean).clamp(0, 255);
        num g = ((pixel.g - mean) * contrastFactor + mean).clamp(0, 255);
        num b = ((pixel.b - mean) * contrastFactor + mean).clamp(0, 255);
        adjustedImage.setPixel(x, y, img.ColorRgb8(r.toInt(), g.toInt(), b.toInt()));
      }
    }
    return adjustedImage;
  }

  Future<List<Face>> _detectFaces(File imageFile) async {
    final preprocessedImage = _preprocessImage(imageFile);
    final inputImage = InputImage.fromFile(preprocessedImage);
    return await faceDetector.processImage(inputImage);
  }

  Map<String, FaceLandmark?> _extractKeyLandmarks(Face face) {
    return {
      'leftEye': face.landmarks[FaceLandmarkType.leftEye],
      'rightEye': face.landmarks[FaceLandmarkType.rightEye],
      'noseBase': face.landmarks[FaceLandmarkType.noseBase],
      'leftMouth': face.landmarks[FaceLandmarkType.leftMouth],
      'rightMouth': face.landmarks[FaceLandmarkType.rightMouth],
      'leftCheek': face.landmarks[FaceLandmarkType.leftCheek],
      'rightCheek': face.landmarks[FaceLandmarkType.rightCheek],
      'leftEar': face.landmarks[FaceLandmarkType.leftEar],
      'rightEar': face.landmarks[FaceLandmarkType.rightEar],
    };
  }

  double _computeLandmarkDistance(Point<int>? p1, Point<int>? p2) {
    if (p1 == null || p2 == null) return double.infinity;
    final offset1 = Offset(p1.x.toDouble(), p1.y.toDouble());
    final offset2 = Offset(p2.x.toDouble(), p2.y.toDouble());
    return sqrt(pow(offset1.dx - offset2.dx, 2) + pow(offset1.dy - offset2.dy, 2));
  }

  Offset _computeMidpoint(Point<int>? p1, Point<int>? p2) {
    if (p1 == null || p2 == null) return Offset.zero;
    return Offset((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
  }

  Map<String, dynamic> _compareFaces(Face face1, Face face2) {
    final landmarks1 = _extractKeyLandmarks(face1);
    final landmarks2 = _extractKeyLandmarks(face2);
    double eyeDistance1 = _computeLandmarkDistance(landmarks1['leftEye']?.position, landmarks1['rightEye']?.position);
    double eyeDistance2 = _computeLandmarkDistance(landmarks2['leftEye']?.position, landmarks2['rightEye']?.position);
    double cheekDistance1 = _computeLandmarkDistance(landmarks1['leftCheek']?.position, landmarks1['rightCheek']?.position);
    double cheekDistance2 = _computeLandmarkDistance(landmarks2['leftCheek']?.position, landmarks2['rightCheek']?.position);
    double earDistance1 = _computeLandmarkDistance(landmarks1['leftEar']?.position, landmarks1['rightEar']?.position);
    double earDistance2 = _computeLandmarkDistance(landmarks2['leftEar']?.position, landmarks2['rightEar']?.position);
    final mouthMidpoint1 = _computeMidpoint(landmarks1['leftMouth']?.position, landmarks1['rightMouth']?.position);
    final mouthMidpoint2 = _computeMidpoint(landmarks2['leftMouth']?.position, landmarks2['rightMouth']?.position);
    double noseToMouth1 = _computeLandmarkDistance(
      landmarks1['noseBase']?.position,
      mouthMidpoint1 != Offset.zero ? Point<int>(mouthMidpoint1.dx.toInt(), mouthMidpoint1.dy.toInt()) : null,
    );
    double noseToMouth2 = _computeLandmarkDistance(
      landmarks2['noseBase']?.position,
      mouthMidpoint2 != Offset.zero ? Point<int>(mouthMidpoint2.dx.toInt(), mouthMidpoint2.dy.toInt()) : null,
    );

    if (eyeDistance1.isInfinite || eyeDistance2.isInfinite ||
        cheekDistance1.isInfinite || cheekDistance2.isInfinite ||
        earDistance1.isInfinite || earDistance2.isInfinite ||
        noseToMouth1.isInfinite || noseToMouth2.isInfinite) {
      return {'percentage': 0.0, 'details': 'Missing landmarks'};
    }

    double avgEyeDistance = (eyeDistance1 + eyeDistance2) / 2;
    if (avgEyeDistance == 0) return {'percentage': 0.0, 'details': 'Invalid eye distance'};
    double eyeRatio1 = eyeDistance1 / avgEyeDistance;
    double eyeRatio2 = eyeDistance2 / avgEyeDistance;
    double cheekRatio1 = cheekDistance1 / avgEyeDistance;
    double cheekRatio2 = cheekDistance2 / avgEyeDistance;
    double earRatio1 = earDistance1 / avgEyeDistance;
    double earRatio2 = earDistance2 / avgEyeDistance;
    double noseMouthRatio1 = noseToMouth1 / avgEyeDistance;
    double noseMouthRatio2 = noseToMouth2 / avgEyeDistance;

    double eyeDiff = (eyeRatio1 - eyeRatio2).abs();
    double cheekDiff = (cheekRatio1 - cheekRatio2).abs();
    double earDiff = (earRatio1 - earRatio2).abs();
    double noseMouthDiff = (noseMouthRatio1 - noseMouthRatio2).abs();

    const double maxDiff = 1.0;
    double eyeSimilarity = ((maxDiff - min(eyeDiff, maxDiff)) / maxDiff) * 100;
    double cheekSimilarity = ((maxDiff - min(cheekDiff, maxDiff)) / maxDiff) * 100;
    double earSimilarity = ((maxDiff - min(earDiff, maxDiff)) / maxDiff) * 100;
    double noseMouthSimilarity = ((maxDiff - min(noseMouthDiff, maxDiff)) / maxDiff) * 100;

    double combinedScore = (eyeDiff + cheekDiff + earDiff + noseMouthDiff) / 4;
    double maxScore = 1.0;
    double matchPercentage = ((maxScore - min(combinedScore, maxScore)) / maxScore) * 100;

    return {
      'percentage': matchPercentage,
      'details': 'Eye: ${eyeSimilarity.toStringAsFixed(1)}%, Cheek: ${cheekSimilarity.toStringAsFixed(1)}%, '
          'Ear: ${earSimilarity.toStringAsFixed(1)}%, Nose-Mouth: ${noseMouthSimilarity.toStringAsFixed(1)}%'
    };
  }

  @override
  void dispose() {
    faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Face Verification',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF3F51B5),
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment, color: Colors.white),
            tooltip: 'View Results',
            onPressed: _navigateToResultScreen,
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
              AnimatedOpacity(
                opacity: _uploadedImages.isNotEmpty ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 500),
                child: Card(
                  elevation: 5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: _uploadedImages.isNotEmpty && _currentImageIndex < _uploadedImages.length
                        ? SizedBox(
                      height: 200,
                      child: Stack(
                        children: [
                          Image.file(
                            _uploadedImages[_currentImageIndex],
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Text(
                              'Image ${_currentImageIndex + 1} of ${_uploadedImages.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                backgroundColor: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                        : Container(
                      height: 200,
                      color: Colors.grey.withOpacity(0.1),
                      child: const Center(
                        child: Text(
                          'No uploaded images',
                          style: TextStyle(color: Colors.black54, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildButton('Upload Images', _pickImagesFromGallery),
              const SizedBox(height: 40),
              AnimatedOpacity(
                opacity: _capturedImage != null ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 500),
                child: Card(
                  elevation: 5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: _capturedImage != null
                        ? Image.file(_capturedImage!, height: 200, fit: BoxFit.cover)
                        : Container(
                      height: 200,
                      color: Colors.grey.withOpacity(0.1),
                      child: const Center(
                        child: Text(
                          'No captured image',
                          style: TextStyle(color: Colors.black54, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildButton('Capture Image', _captureImage),
              const SizedBox(height: 40),
              _buildButton('Verify Faces', _verifyFaces, isLoading: _isVerifying),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed, {bool isLoading = false}) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        elevation: 5,
      ),
      child: isLoading
          ? Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Verifying...',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      )
          : Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}