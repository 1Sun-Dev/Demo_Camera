import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error getting cameras: $e');
  }
  runApp(const CameraApp());
}

class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera App',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.black,
      ),
      home: const CameraScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  
  // Camera settings
  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.auto;
  bool _isRecordingMode = false; // false = photo, true = video
  
  // Video recording state
  bool _isRecordingVideo = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  
  // Blinking red dot animation
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;
  
  // Last capture
  String? _lastCapturePath;
  bool _isLastCaptureVideo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _blinkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_blinkController);
    
    if (cameras.isNotEmpty) {
      _initializeCamera(cameras[_selectedCameraIndex]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _recordingTimer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
      _isCameraInitialized = false;
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(cameraController.description);
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    final previousController = _controller;
    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: true,
    );

    await previousController?.dispose();

    if (mounted) {
      setState(() {
        _controller = cameraController;
      });
    }

    cameraController.addListener(() {
      if (mounted) setState(() {});
      if (cameraController.value.hasError) {
        final errorDescription = cameraController.value.errorDescription ?? '';
        if (errorDescription.contains('torchModeNotSupported')) {
          return;
        }
        _showErrorSnackBar('Lỗi camera: $errorDescription');
      }
    });

    try {
      await cameraController.initialize();
      await _applyFlashMode(_flashMode, showError: false);
      _isCameraInitialized = true;
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          _showErrorSnackBar('Chưa cấp quyền truy cập camera.');
          break;
        case 'AudioAccessDenied':
          _showErrorSnackBar('Chưa cấp quyền truy cập micro.');
          break;
        case 'torchModeNotSupported':
          _showErrorSnackBar('Thiết bị này không hỗ trợ đèn flash camera.');
          setState(() {
            _flashMode = FlashMode.off;
          });
          break;
        default:
          _showErrorSnackBar('Lỗi khởi tạo camera: ${e.code}');
          break;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _applyFlashMode(FlashMode mode, {bool showError = true}) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _controller!.setFlashMode(mode);
      if (mounted) {
        setState(() {
          _flashMode = mode;
        });
      }
    } on CameraException catch (e) {
      if (e.code == 'torchModeNotSupported' || e.description?.contains('torchModeNotSupported') == true) {
        if (mounted) {
          setState(() {
            _flashMode = FlashMode.off;
          });
        }
        if (showError) {
          _showErrorSnackBar('Thiết bị này không hỗ trợ đèn flash camera.');
        }
        return;
      }
      rethrow;
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _switchCamera() async {
    if (cameras.length < 2) return;
    
    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
    await _initializeCamera(cameras[_selectedCameraIndex]);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;

    FlashMode nextMode;
    switch (_flashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.always;
        break;
      case FlashMode.always:
        nextMode = FlashMode.off;
        break;
      case FlashMode.torch:
        nextMode = FlashMode.off;
        break;
    }

    try {
      await _applyFlashMode(nextMode);
    } on CameraException catch (e) {
      if (e.code == 'torchModeNotSupported' || e.description?.contains('torchModeNotSupported') == true) {
        setState(() {
          _flashMode = FlashMode.off;
        });
        _showErrorSnackBar('Thiết bị này không hỗ trợ đèn flash camera.');
        return;
      }
      _showErrorSnackBar('Không thể chuyển chế độ flash');
    } catch (e) {
      _showErrorSnackBar('Không thể chuyển chế độ flash');
    }
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    try {
      final XFile picture = await _controller!.takePicture();
      setState(() {
        _lastCapturePath = picture.path;
        _isLastCaptureVideo = false;
      });
      _openPreviewScreen(picture.path, false);
    } catch (e) {
      _showErrorSnackBar('Lỗi khi chụp ảnh: $e');
    }
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isRecordingVideo) return;

    try {
      await _controller!.startVideoRecording();
      
      setState(() {
        _isRecordingVideo = true;
        _recordingDuration = 0;
      });
      
      _blinkController.repeat(reverse: true);
      
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration++;
        });
      });
    } catch (e) {
      _showErrorSnackBar('Lỗi khi quay video: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) return;

    try {
      final XFile video = await _controller!.stopVideoRecording();
      
      _recordingTimer?.cancel();
      _blinkController.stop();
      
      setState(() {
        _isRecordingVideo = false;
        _lastCapturePath = video.path;
        _isLastCaptureVideo = true;
      });
      
      _openPreviewScreen(video.path, true);
    } catch (e) {
      _showErrorSnackBar('Lỗi khi dừng quay video: $e');
    }
  }

  void _openPreviewScreen(String filePath, bool isVideo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreviewScreen(
          filePath: filePath,
          isVideo: isVideo,
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (cameras.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Không tìm thấy camera trên thiết bị'),
        ),
      );
    }

    if (!_isCameraInitialized) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Đang khởi tạo camera...',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Preview
            Center(
              child: _buildCameraPreview(),
            ),
            
            // Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            
            // Recording Timer
            if (_isRecordingVideo)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: _buildRecordingTimer(),
              ),
              
            // Bottom Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Text(
        'Đang khởi tạo camera...',
        style: TextStyle(color: Colors.white),
      );
    }
    
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _controller!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    
    return Transform.scale(
      scale: scale,
      child: Center(
        child: CameraPreview(_controller!),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black45,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(_getFlashIcon(), color: Colors.white),
            onPressed: _isRecordingVideo ? null : _toggleFlash,
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: _isRecordingVideo ? null : _switchCamera,
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecordingTimer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FadeTransition(
          opacity: _blinkAnimation,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatDuration(_recordingDuration),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode Switcher
          if (!_isRecordingVideo)
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isRecordingMode = false;
                      });
                    },
                    child: Text(
                      'ẢNH',
                      style: TextStyle(
                        color: !_isRecordingMode ? Colors.yellow : Colors.white,
                        fontWeight: !_isRecordingMode ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 30),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isRecordingMode = true;
                      });
                    },
                    child: Text(
                      'VIDEO',
                      style: TextStyle(
                        color: _isRecordingMode ? Colors.yellow : Colors.white,
                        fontWeight: _isRecordingMode ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Thumbnail
              GestureDetector(
                onTap: _lastCapturePath == null ? null : () => _openPreviewScreen(_lastCapturePath!, _isLastCaptureVideo),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    image: _lastCapturePath != null && !_isLastCaptureVideo
                        ? DecorationImage(
                            image: FileImage(File(_lastCapturePath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _isLastCaptureVideo
                      ? const Icon(Icons.play_arrow, color: Colors.white)
                      : (_lastCapturePath == null ? null : const SizedBox()),
                ),
              ),
              
              // Capture Button
              GestureDetector(
                onTap: () {
                  if (_isRecordingMode) {
                    if (_isRecordingVideo) {
                      _stopVideoRecording();
                    } else {
                      _startVideoRecording();
                    }
                  } else {
                    _takePicture();
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: _isRecordingVideo ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: _isRecordingVideo ? BorderRadius.circular(8) : null,
                      color: _isRecordingMode ? Colors.red : Colors.white,
                    ),
                  ),
                ),
              ),
              
              // Empty space for balance
              const SizedBox(width: 50, height: 50),
            ],
          ),
        ],
      ),
    );
  }
}

class PreviewScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const PreviewScreen({
    super.key,
    required this.filePath,
    required this.isVideo,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  VideoPlayerController? _videoPlayerController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideoPlayer();
    }
  }

  Future<void> _initVideoPlayer() async {
    _videoPlayerController = VideoPlayerController.file(File(widget.filePath));
    await _videoPlayerController!.initialize();
    
    _videoPlayerController!.addListener(() {
      if (mounted) {
        setState(() {
          _isPlaying = _videoPlayerController!.value.isPlaying;
        });
      }
    });
    
    setState(() {});
    await _videoPlayerController!.play();
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _deleteFile() async {
    try {
      await File(widget.filePath).delete();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lỗi khi xóa file')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Xem trước'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteFile,
          ),
        ],
      ),
      body: Center(
        child: widget.isVideo ? _buildVideoPreview() : _buildImagePreview(),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Image.file(
      File(widget.filePath),
      fit: BoxFit.contain,
    );
  }

  Widget _buildVideoPreview() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) {
      return const CircularProgressIndicator();
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoPlayerController!.value.aspectRatio,
          child: VideoPlayer(_videoPlayerController!),
        ),
        if (!_isPlaying)
          GestureDetector(
            onTap: () {
              _videoPlayerController!.play();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 50,
              ),
            ),
          ),
        GestureDetector(
          onTap: () {
            if (_isPlaying) {
              _videoPlayerController!.pause();
            } else {
              _videoPlayerController!.play();
            }
          },
          child: Container(
            color: Colors.transparent,
          ),
        ),
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: VideoProgressIndicator(
            _videoPlayerController!,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: Colors.red,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}
