import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:page_flip/page_flip.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const PdfReaderScreen(),
    );
  }
}

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  PdfDocument? _pdfDocument;
  bool _isLoading = true;
  int _totalPages = 0;
  int _currentPage = 1;
  bool _isRightToLeft = true; // デフォルト右開き

  final Map<int, ImageProvider> _pageCache = {};
  final _controller = GlobalKey<PageFlipWidgetState>();

  final String _samplePdfUrl =
      'https://raw.githubusercontent.com/mozilla/pdf.js/ba2edeae/web/compressed.tracemonkey-pldi09.pdf';

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final response = await http.get(Uri.parse(_samplePdfUrl));
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sample.pdf');
      await file.writeAsBytes(response.bodyBytes);

      final doc = await PdfDocument.openFile(file.path);
      setState(() {
        _pdfDocument = doc;
        _totalPages = doc.pagesCount;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading PDF: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<ImageProvider> _getPageImage(int pageNumber) async {
    if (_pageCache.containsKey(pageNumber)) {
      return _pageCache[pageNumber]!;
    }

    if (_pdfDocument == null) throw Exception("Document not loaded");

    final page = await _pdfDocument!.getPage(pageNumber);
    final pageImage = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: PdfPageImageFormat.jpeg,
    );
    await page.close();

    final provider = MemoryImage(pageImage!.bytes);
    _pageCache[pageNumber] = provider;
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pdfDocument == null
              ? const Center(child: Text('PDFの読み込みに失敗しました'))
              : SafeArea(
                  child: Column(
                    children: [
                      // 上部操作バー
                      Container(
                        color: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            DropdownButton<int>(
                              value: _currentPage,
                              dropdownColor: Colors.grey[900],
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              items: List.generate(_totalPages, (index) {
                                return DropdownMenuItem(
                                  value: index + 1,
                                  child: Text('${index + 1} / $_totalPages ページ'),
                                );
                              }),
                              onChanged: (value) {
                                if (value != null) {
                                  _controller.currentState?.goToPage(value - 1);
                                  setState(() {
                                    _currentPage = value;
                                  });
                                }
                              },
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isRightToLeft = !_isRightToLeft;
                                });
                              },
                              icon: Icon(
                                _isRightToLeft ? Icons.arrow_back : Icons.arrow_forward,
                                color: Colors.white,
                              ),
                              label: Text(
                                _isRightToLeft ? '← 右開き' : '左開き →',
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // 真ん中水平めくり対応の3Dエリア
                      Expanded(
                        child: Container(
                          color: Colors.black,
                          child: PageFlipWidget(
                            key: _controller,
                            isAcrossScale: true,
                            // 右開き/左開きの読み込み順序・ドラッグ方向の切替
                            children: List.generate(_totalPages, (index) {
                              final pageNum = _isRightToLeft ? (index + 1) : (_totalPages - index);
                              return FutureBuilder<ImageProvider>(
                                future: _getPageImage(pageNum),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                                    return SizedBox.expand(
                                      child: Image(
                                        image: snapshot.data!,
                                        fit: BoxFit.fill,
                                      ),
                                    );
                                  } else {
                                    return Container(
                                      color: Colors.white,
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                },
                              );
                            }),
                          ),
                        ),
                      ),

                      // 下部スライダー
                      Container(
                        color: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Slider(
                          value: _currentPage.toDouble(),
                          min: 1,
                          max: _totalPages.toDouble(),
                          divisions: _totalPages > 1 ? _totalPages - 1 : 1,
                          onChanged: (value) {
                            _controller.currentState?.goToPage(value.toInt() - 1);
                            setState(() {
                              _currentPage = value.toInt();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
