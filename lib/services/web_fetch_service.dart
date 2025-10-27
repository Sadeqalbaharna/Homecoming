import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:typed_data';

/// Service for fetching and parsing web content
/// Provides cleaned text extraction from websites for AI consumption
class WebFetchService {
  final Dio _dio;
  final Map<String, WebPageCache> _cache = {};
  static const Duration _cacheExpiry = Duration(hours: 1);

  WebFetchService() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  ));

  /// Fetch and parse a webpage or PDF, returning cleaned text content
  /// Returns null if fetching fails
  Future<WebPageResult?> fetchWebPage(String url) async {
    try {
      print('🌐 [WEB FETCH] Fetching: $url');
      
      // Check cache first
      if (_cache.containsKey(url)) {
        final cached = _cache[url]!;
        if (DateTime.now().difference(cached.timestamp) < _cacheExpiry) {
          print('📦 [WEB FETCH] Using cached content for: $url');
          return cached.result;
        } else {
          _cache.remove(url); // Expired
        }
      }

      // Check if URL is a PDF
      if (url.toLowerCase().endsWith('.pdf')) {
        return await _fetchPdfContent(url);
      }

      // Fetch the webpage
      final response = await _dio.get(url);
      
      if (response.statusCode != 200) {
        print('❌ [WEB FETCH] Failed with status ${response.statusCode}');
        return null;
      }

      // Parse HTML
      final document = html_parser.parse(response.data);
      
      // Extract content with enhanced methods
      final title = _extractTitle(document);
      final content = _extractContent(document);
      final description = _extractDescription(document);
      final structuredData = _extractStructuredData(document);
      final tables = _extractTables(document);
      
      // Combine all content
      final combinedContent = _combineContent(content, structuredData, tables);
      
      final result = WebPageResult(
        url: url,
        title: title,
        content: combinedContent,
        description: description,
        fetchedAt: DateTime.now(),
      );

      // Cache the result
      _cache[url] = WebPageCache(result: result, timestamp: DateTime.now());
      
      print('✅ [WEB FETCH] Successfully fetched: $title (${combinedContent.length} chars)');
      return result;
      
    } on DioException catch (e) {
      print('❌ [WEB FETCH] Dio error: ${e.type} - ${e.message}');
      return null;
    } catch (e) {
      print('❌ [WEB FETCH] Error fetching $url: $e');
      return null;
    }
  }

  /// Extract the page title
  String _extractTitle(dom.Document document) {
    // Try meta og:title first
    final ogTitle = document.querySelector('meta[property="og:title"]');
    if (ogTitle != null) {
      final content = ogTitle.attributes['content'];
      if (content != null && content.isNotEmpty) return content;
    }
    
    // Try regular title tag
    final titleElement = document.querySelector('title');
    if (titleElement != null && titleElement.text.isNotEmpty) {
      return titleElement.text.trim();
    }
    
    return 'Untitled Page';
  }

  /// Extract meta description
  String? _extractDescription(dom.Document document) {
    // Try meta og:description
    final ogDesc = document.querySelector('meta[property="og:description"]');
    if (ogDesc != null) {
      final content = ogDesc.attributes['content'];
      if (content != null && content.isNotEmpty) return content;
    }
    
    // Try meta description
    final metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc != null) {
      final content = metaDesc.attributes['content'];
      if (content != null && content.isNotEmpty) return content;
    }
    
    return null;
  }

  /// Extract main content from the page
  String _extractContent(dom.Document document) {
    // Remove unwanted elements
    final unwantedSelectors = [
      'script', 'style', 'nav', 'header', 'footer', 
      'aside', 'iframe', 'noscript', '.ad', '#ad', '.advertisement'
    ];
    
    for (final selector in unwantedSelectors) {
      document.querySelectorAll(selector).forEach((element) => element.remove());
    }

    // Try to find main content area
    final mainSelectors = [
      'article',
      'main',
      '[role="main"]',
      '.content',
      '.post-content',
      '.article-content',
      '#content',
      'body',
    ];

    dom.Element? mainContent;
    for (final selector in mainSelectors) {
      mainContent = document.querySelector(selector);
      if (mainContent != null) break;
    }

    // Extract text
    final text = mainContent?.text ?? document.body?.text ?? '';
    
    // Clean up the text
    return _cleanText(text);
  }

  /// Clean extracted text (remove extra whitespace, etc.)
  String _cleanText(String text) {
    // Remove extra whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    
    // Remove leading/trailing whitespace
    text = text.trim();
    
    // Limit length (for AI context window)
    const maxLength = 8000; // ~2000 tokens
    if (text.length > maxLength) {
      text = '${text.substring(0, maxLength)}... [truncated]';
    }
    
    return text;
  }

  /// Fetch and parse PDF content
  Future<WebPageResult?> _fetchPdfContent(String url) async {
    try {
      print('📄 [WEB FETCH] Fetching PDF: $url');
      
      // Download PDF
      final response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      
      if (response.statusCode != 200) {
        print('❌ [WEB FETCH] Failed to download PDF');
        return null;
      }

      // Extract text from PDF using Syncfusion
      final Uint8List pdfBytes = Uint8List.fromList(response.data);
      final PdfDocument document = PdfDocument(inputBytes: pdfBytes);
      
      // Extract text from all pages
      final StringBuffer textBuffer = StringBuffer();
      for (int i = 0; i < document.pages.count; i++) {
        final PdfTextExtractor extractor = PdfTextExtractor(document);
        final String pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        textBuffer.writeln(pageText);
      }
      
      document.dispose();

      final cleanedText = _cleanText(textBuffer.toString());
      
      final result = WebPageResult(
        url: url,
        title: 'PDF Document',
        content: cleanedText,
        description: 'PDF file from $url',
        fetchedAt: DateTime.now(),
      );

      // Cache the result
      _cache[url] = WebPageCache(result: result, timestamp: DateTime.now());
      
      print('✅ [WEB FETCH] Successfully extracted PDF text (${cleanedText.length} chars)');
      return result;
      
    } catch (e) {
      print('❌ [WEB FETCH] Error fetching PDF: $e');
      return null;
    }
  }

  /// Extract structured data (Schema.org, JSON-LD)
  String _extractStructuredData(dom.Document document) {
    final buffer = StringBuffer();
    
    // Look for JSON-LD structured data (common for pricing/products)
    final jsonLdElements = document.querySelectorAll('script[type="application/ld+json"]');
    for (final element in jsonLdElements) {
      final jsonText = element.text.trim();
      if (jsonText.isNotEmpty) {
        // Check if it contains pricing/product info
        if (jsonText.contains('"price"') || 
            jsonText.contains('"Product"') || 
            jsonText.contains('"Offer"') ||
            jsonText.contains('"PriceSpecification"')) {
          buffer.writeln('\n[Structured Data - Pricing Info]:');
          buffer.writeln(jsonText);
        }
      }
    }
    
    // Look for microdata pricing (common pattern)
    final priceElements = document.querySelectorAll('[itemprop="price"], .price, [class*="price"]');
    if (priceElements.isNotEmpty) {
      buffer.writeln('\n[Detected Prices]:');
      for (final element in priceElements) {
        final priceText = element.text.trim();
        if (priceText.isNotEmpty && priceText.length < 100) {
          buffer.writeln('- $priceText');
        }
      }
    }
    
    return buffer.toString();
  }

  /// Extract and format tables (great for pricing comparisons)
  String _extractTables(dom.Document document) {
    final buffer = StringBuffer();
    final tables = document.querySelectorAll('table');
    
    for (var i = 0; i < tables.length; i++) {
      final table = tables[i];
      
      // Check if table might contain pricing info
      final tableText = table.text.toLowerCase();
      if (!tableText.contains('price') && 
          !tableText.contains('plan') && 
          !tableText.contains('tier') &&
          !tableText.contains('subscription') &&
          !tableText.contains('\$') &&
          !tableText.contains('€') &&
          !tableText.contains('£')) {
        continue; // Skip tables without pricing keywords
      }
      
      buffer.writeln('\n[Table ${i + 1} - Pricing/Features]:');
      
      // Extract headers
      final headers = table.querySelectorAll('th, thead td');
      if (headers.isNotEmpty) {
        buffer.write('| ');
        for (final header in headers) {
          buffer.write('${header.text.trim()} | ');
        }
        buffer.writeln();
        buffer.writeln('| ${List.filled(headers.length, '---').join(' | ')} |');
      }
      
      // Extract rows
      final rows = table.querySelectorAll('tbody tr, tr');
      for (final row in rows) {
        final cells = row.querySelectorAll('td, th');
        if (cells.isNotEmpty) {
          buffer.write('| ');
          for (final cell in cells) {
            final cellText = cell.text.trim().replaceAll('\n', ' ');
            buffer.write('$cellText | ');
          }
          buffer.writeln();
        }
      }
      buffer.writeln();
    }
    
    return buffer.toString();
  }

  /// Combine all content sources
  String _combineContent(String mainContent, String structuredData, String tables) {
    final buffer = StringBuffer();
    
    // Add main content first
    buffer.writeln(mainContent);
    
    // Add structured data if present
    if (structuredData.isNotEmpty) {
      buffer.writeln('\n=== STRUCTURED PRICING DATA ===');
      buffer.writeln(structuredData);
    }
    
    // Add tables if present
    if (tables.isNotEmpty) {
      buffer.writeln('\n=== PRICING TABLES ===');
      buffer.writeln(tables);
    }
    
    return _cleanText(buffer.toString());
  }

  /// Fetch multiple URLs concurrently
  Future<List<WebPageResult>> fetchMultiplePages(List<String> urls) async {
    print('🌐 [WEB FETCH] Fetching ${urls.length} pages concurrently...');
    
    final results = await Future.wait(
      urls.map((url) => fetchWebPage(url)),
    );
    
    return results.whereType<WebPageResult>().toList();
  }

  /// Clear cache
  void clearCache() {
    _cache.clear();
    print('🗑️ [WEB FETCH] Cache cleared');
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cached_pages': _cache.length,
      'urls': _cache.keys.toList(),
    };
  }
}

/// Result of a web page fetch
class WebPageResult {
  final String url;
  final String title;
  final String content;
  final String? description;
  final DateTime fetchedAt;

  WebPageResult({
    required this.url,
    required this.title,
    required this.content,
    this.description,
    required this.fetchedAt,
  });

  /// Format for AI consumption
  String toAIContext() {
    final buffer = StringBuffer();
    buffer.writeln('--- Web Page Content ---');
    buffer.writeln('URL: $url');
    buffer.writeln('Title: $title');
    if (description != null) {
      buffer.writeln('Description: $description');
    }
    buffer.writeln('Fetched: ${fetchedAt.toLocal()}');
    buffer.writeln('\nContent:\n$content');
    buffer.writeln('--- End of Web Page ---');
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'content': content,
    'description': description,
    'fetched_at': fetchedAt.toIso8601String(),
  };
}

/// Cache entry for web pages
class WebPageCache {
  final WebPageResult result;
  final DateTime timestamp;

  WebPageCache({
    required this.result,
    required this.timestamp,
  });
}
