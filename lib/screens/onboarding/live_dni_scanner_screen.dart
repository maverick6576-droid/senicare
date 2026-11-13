import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';

class LiveDniScannerScreen extends StatefulWidget {
  const LiveDniScannerScreen({super.key});

  @override
  State<LiveDniScannerScreen> createState() => _LiveDniScannerScreenState();
}

class _LiveDniScannerScreenState extends State<LiveDniScannerScreen> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _isProcessing = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El escáner en vivo solo está disponible en Android/iOS.')),
          );
          Navigator.pop(context);
        }
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontró ninguna cámara disponible en el dispositivo.')),
          );
          Navigator.pop(context);
        }
        return;
      }
      final camera = cameras.first;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() => _isInitialized = true);

      _cameraController!.startImageStream((CameraImage image) {
        if (_isProcessing) return;
        _isProcessing = true;
        _processImage(image, camera);
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la cámara: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _processImage(CameraImage image, CameraDescription camera) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      bool dniFound = false;
      String foundDni = '';

      final RegExp dniRegExp = RegExp(r'\b[0-9]{8}[A-Z]\b');
      final RegExp nieRegExp = RegExp(r'\b[XYZ][0-9]{7}[A-Z]\b');

      for (TextBlock block in recognizedText.blocks) {
        final text = block.text.toUpperCase();
        if (dniRegExp.hasMatch(text)) {
          dniFound = true;
          foundDni = dniRegExp.firstMatch(text)!.group(0)!;
          break;
        } else if (nieRegExp.hasMatch(text)) {
          dniFound = true;
          foundDni = nieRegExp.firstMatch(text)!.group(0)!;
          break;
        }
      }

      if (dniFound) {
        await _cameraController!.stopImageStream();
        final xFile = await _cameraController!.takePicture();
        if (mounted) {
          Navigator.pop(context, {
            'path': xFile.path,
            'text': 'DNI/NIE Detectado: $foundDni\n${recognizedText.text}',
          });
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _takeManualPicture() async {
    try {
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      final xFile = await _cameraController!.takePicture();
      String ocrText = '';
      try {
        final recognized = await _textRecognizer.processImage(InputImage.fromFilePath(xFile.path));
        ocrText = recognized.text;
      } catch (_) {}
      if (mounted) {
        Navigator.pop(context, {
          'path': xFile.path,
          'text': ocrText.isNotEmpty ? ocrText : 'Captura manual',
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraController == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          // Overlay
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.7), BlendMode.srcOut),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut),
                ),
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    height: MediaQuery.of(context).size.width * 0.85 * 0.63, // Proporción aproximada ID
                    decoration: BoxDecoration(
                      color: Colors.white, // Se vuelve transparente gracias al srcOut
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Borde visual
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.width * 0.85 * 0.63,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Instrucciones
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: const Text(
              'Encuadra tu DNI/NIE en el recuadro\nSe capturará automáticamente',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          // Botón manual
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                onPressed: _takeManualPicture,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tomar foto manualmente'),
              ),
            ),
          ),
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
