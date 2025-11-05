/// Mind Map Screen - Obsidian-style knowledge graph visualization
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../models/knowledge_node.dart';
import '../services/knowledge_graph_service.dart';
import '../widgets/graph_canvas.dart';
import '../widgets/node_detail_card.dart';

class MindMapScreen extends StatefulWidget {
  final String personaId;

  const MindMapScreen({
    super.key,
    required this.personaId,
  });

  @override
  State<MindMapScreen> createState() => _MindMapScreenState();
}

class _MindMapScreenState extends State<MindMapScreen> with TickerProviderStateMixin {
  final KnowledgeGraphService _graphService = KnowledgeGraphService();
  
  KnowledgeGraph? _graph;
  bool _isLoading = true;
  String? _error;
  double _loadingProgress = 0.0;
  String _loadingStatus = 'Initializing...';
  Timer? _timeoutTimer;
  
  // View state
  final TransformationController _transformationController = TransformationController();
  
  // Selection
  KnowledgeNode? _selectedNode;
  Set<String> _highlightedNodeIds = {};
  
  // Animation
  late AnimationController _forceAnimationController;
  bool _isAnimating = false;
  
  // Filters
  Set<NodeType> _visibleTypes = NodeType.values.toSet();

  @override
  void initState() {
    super.initState();
    print('🗺️ [MindMap] initState called for personaId: ${widget.personaId}');
    _forceAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    print('🗺️ [MindMap] Starting graph load...');
    _loadGraph();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _forceAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadGraph() async {
    print('🗺️ [MindMap] _loadGraph started');
    setState(() {
      _isLoading = true;
      _error = null;
      _loadingProgress = 0.0;
      _loadingStatus = 'Loading from Firebase...';
    });
    print('🗺️ [MindMap] Loading state set, isLoading: $_isLoading');

    // Set a timeout - if loading takes more than 10 seconds, fail gracefully
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (_isLoading && mounted) {
        print('❌ [MindMap] Loading timeout - returning to overlay');
        setState(() {
          _error = 'Loading timeout - Firebase may be slow or offline';
          _isLoading = false;
        });
        // Auto-close after timeout
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    });

    try {
      setState(() {
        _loadingProgress = 0.2;
        _loadingStatus = 'Connecting to Firebase...';
      });
      print('🗺️ [MindMap] Calling buildGraph with personaId: ${widget.personaId}');
      
      final graph = await _graphService.buildGraph(
        personaId: widget.personaId,
        forceRebuild: false,
      );
      
      print('🗺️ [MindMap] buildGraph returned with ${graph.nodes.length} nodes and ${graph.edges.length} edges');
      _timeoutTimer?.cancel(); // Cancel timeout if successful
      
      setState(() {
        _loadingProgress = 0.6;
        _loadingStatus = 'Processing nodes...';
      });
      
      // Safety check: ensure graph has valid data
      if (graph.nodes.isEmpty) {
        print('⚠️ [MindMap] Graph is empty, showing empty state');
        setState(() {
          _graph = graph;
          _isLoading = false;
          _loadingProgress = 1.0;
        });
        return;
      }
      
      setState(() {
        _loadingProgress = 0.8;
        _loadingStatus = 'Initializing layout...';
      });
      
      // Initialize node positions in a circle
      _initializeNodePositions(graph);
      
      setState(() {
        _graph = graph;
        _isLoading = false;
        _loadingProgress = 1.0;
        _loadingStatus = 'Complete!';
      });
      
      // Start force-directed layout animation
      _startForceSimulation();
    } catch (e, stackTrace) {
      print('❌ [MindMap] Error loading graph: $e');
      print('❌ [MindMap] Stack trace: $stackTrace');
      _timeoutTimer?.cancel();
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      
      // Auto-close after error
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _error != null) {
          print('🔙 [MindMap] Auto-closing due to error');
          Navigator.of(context).pop();
        }
      });
    }
  }

  /// Initialize nodes in a circular layout
  void _initializeNodePositions(KnowledgeGraph graph) {
    final centerX = 400.0;
    final centerY = 400.0;
    final radius = 300.0;
    
    for (var i = 0; i < graph.nodes.length; i++) {
      final angle = (i / graph.nodes.length) * 2 * pi;
      graph.nodes[i].x = centerX + radius * cos(angle);
      graph.nodes[i].y = centerY + radius * sin(angle);
    }
  }

  /// Start force-directed layout simulation
  void _startForceSimulation() {
    if (_graph == null || _isAnimating) return;
    
    _isAnimating = true;
    
    _forceAnimationController.addListener(() {
      if (_graph != null) {
        _applyForces(_graph!);
        setState(() {});
      }
    });
    
    _forceAnimationController.repeat();
    
    // Stop after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      _forceAnimationController.stop();
      _isAnimating = false;
    });
  }

  /// Apply force-directed layout physics
  void _applyForces(KnowledgeGraph graph) {
    const double repulsionStrength = 500.0;
    const double attractionStrength = 0.01;
    const double damping = 0.9;
    
    // Reset forces
    for (final node in graph.nodes) {
      node.vx = 0;
      node.vy = 0;
    }
    
    // 1. Repulsion between all nodes
    for (var i = 0; i < graph.nodes.length; i++) {
      for (var j = i + 1; j < graph.nodes.length; j++) {
        final node1 = graph.nodes[i];
        final node2 = graph.nodes[j];
        
        final dx = node2.x - node1.x;
        final dy = node2.y - node1.y;
        final distance = sqrt(dx * dx + dy * dy);
        
        if (distance > 0) {
          final force = repulsionStrength / (distance * distance);
          node1.vx -= (dx / distance) * force;
          node1.vy -= (dy / distance) * force;
          node2.vx += (dx / distance) * force;
          node2.vy += (dy / distance) * force;
        }
      }
    }
    
    // 2. Attraction along edges
    for (final edge in graph.edges) {
      final node1 = graph.getNode(edge.fromId);
      final node2 = graph.getNode(edge.toId);
      
      if (node1 != null && node2 != null) {
        final dx = node2.x - node1.x;
        final dy = node2.y - node1.y;
        final distance = sqrt(dx * dx + dy * dy);
        
        final force = distance * attractionStrength * edge.strength;
        node1.vx += (dx / distance) * force;
        node1.vy += (dy / distance) * force;
        node2.vx -= (dx / distance) * force;
        node2.vy -= (dy / distance) * force;
      }
    }
    
    // 3. Apply velocities with damping
    for (final node in graph.nodes) {
      node.x += node.vx;
      node.y += node.vy;
      node.vx *= damping;
      node.vy *= damping;
    }
  }

  void _onNodeTap(KnowledgeNode node) {
    setState(() {
      _selectedNode = node;
      
      // Highlight connected nodes
      _highlightedNodeIds = {node.id};
      final connectedNodes = _graph!.getConnectedNodes(node.id);
      _highlightedNodeIds.addAll(connectedNodes.map((n) => n.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedNode = null;
      _highlightedNodeIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    print('🗺️ [MindMap] Building UI - isLoading: $_isLoading, error: $_error, hasGraph: ${_graph != null}, nodeCount: ${_graph?.nodes.length ?? 0}');
    
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E), // Dark background like Obsidian
      appBar: AppBar(
        title: const Text('Knowledge Graph'),
        backgroundColor: const Color(0xFF2D2D2D),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            print('🗺️ [MindMap] Back button pressed');
            Navigator.of(context).pop();
          },
          tooltip: 'Back',
        ),
        actions: [
          // Archive status
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _showArchiveDialog(),
            tooltip: 'Archive Status',
          ),
          // Search
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(),
          ),
          // Filter
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(),
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadGraph(),
          ),
          // Center view
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () {
              setState(() {
                _transformationController.value = Matrix4.identity();
              });
            },
          ),
          // Close button
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          // Floating exit button - always visible for emergency exits
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'exit_button',
              onPressed: () {
                print('🚪 [MindMap] Emergency exit button pressed');
                Navigator.of(context).pop();
              },
              backgroundColor: Colors.red.withOpacity(0.8),
              child: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Close Mind Map',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    print('🗺️ [MindMap] _buildBody called - isLoading: $_isLoading, error: $_error, hasGraph: ${_graph != null}, nodeCount: ${_graph?.nodes.length ?? 0}, progress: $_loadingProgress');
    
    if (_isLoading) {
      print('🗺️ [MindMap] Showing loading with progress: $_loadingProgress - $_loadingStatus');
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _loadingStatus,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _loadingProgress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.purple),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_loadingProgress * 100).toInt()}%',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 24),
              Text(
                'Loading may take up to 10 seconds...',
                style: const TextStyle(color: Colors.white24, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  print('🔙 [MindMap] User cancelled loading');
                  _timeoutTimer?.cancel();
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      print('🗺️ [MindMap] Showing error: $_error');
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to load knowledge graph',
                style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _loadGraph,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      print('🔙 [MindMap] User closed error screen');
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Returning to overlay automatically in 3 seconds...',
                style: TextStyle(color: Colors.white24, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_graph == null || _graph!.nodes.isEmpty) {
      print('🗺️ [MindMap] Showing empty state');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bubble_chart_outlined, size: 64, color: Colors.white30),
            const SizedBox(height: 16),
            const Text(
              'No memories yet',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start chatting with Kai to build the knowledge graph',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    print('🗺️ [MindMap] Rendering graph with ${_graph!.nodes.length} nodes');
    return Stack(
      children: [
        // Graph canvas
        GestureDetector(
          onTapUp: (details) {
            // Check if tapped on background (not a node)
            if (_selectedNode != null) {
              _clearSelection();
            }
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                setState(() {
                  // Zoom with mouse wheel - adjust transformation matrix
                  final delta = event.scrollDelta.dy;
                  final scale = (_transformationController.value.getMaxScaleOnAxis() - delta * 0.001).clamp(0.1, 5.0);
                  _transformationController.value = Matrix4.identity()..scale(scale);
                });
              }
            },
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.1,
              maxScale: 5.0,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: GraphCanvas(
                graph: _graph!,
                selectedNode: _selectedNode,
                highlightedNodeIds: _highlightedNodeIds,
                visibleTypes: _visibleTypes,
                onNodeTap: _onNodeTap,
              ),
            ),
          ),
        ),
        
        // Node detail card
        if (_selectedNode != null)
          Positioned(
            right: 16,
            top: 16,
            child: NodeDetailCard(
              node: _selectedNode!,
              graph: _graph!,
              onClose: _clearSelection,
              onPinMemory: (node) {
                // TODO: Implement pinning
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Pinned: ${node.label}')),
                );
              },
            ),
          ),
        
        // Stats overlay
        Positioned(
          left: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_graph!.nodes.length} nodes',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${_graph!.edges.length} connections',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Zoom: ${(_transformationController.value.getMaxScaleOnAxis() * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSearchDialog() {
    // TODO: Implement search
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Search coming soon!')),
    );
  }
  
  void _showArchiveDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading archive status...'),
          ],
        ),
      ),
    );
    
    try {
      final stats = await _graphService.getArchiveStats(widget.personaId);
      
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.archive, color: Colors.blue),
              SizedBox(width: 8),
              Text('Archive Status'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Last Archived: ${_formatDateTime(stats.lastArchivedTime)}'),
              const SizedBox(height: 8),
              Text('Total Conversations: ${stats.totalConversations}'),
              Text('Archived: ${stats.totalArchived}'),
              Text('Unarchived: ${stats.unarchivedCount}'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: stats.completionPercentage / 100,
                backgroundColor: Colors.grey[300],
                color: stats.isUpToDate ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 4),
              Text(
                '${stats.completionPercentage.toStringAsFixed(1)}% complete',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (!stats.isUpToDate) ...[
                const SizedBox(height: 16),
                Text(
                  '${stats.unarchivedCount} conversations need archiving',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Everything is archived!',
                      style: TextStyle(color: Colors.green),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (!stats.isUpToDate)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _archiveNow();
                },
                icon: const Icon(Icons.download),
                label: const Text('Archive Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading archive stats: $e')),
      );
    }
  }
  
  void _archiveNow() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Archiving conversations...'),
            SizedBox(height: 8),
            Text(
              'This may take a moment',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
    
    try {
      final result = await _graphService.archiveUnprocessedData(
        personaId: widget.personaId,
      );
      
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Archived ${result.conversationsArchived} conversations\n'
              'Created ${result.nodesCreated} nodes, ${result.edgesCreated} edges',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        
        // Reload graph to show new data
        _loadGraph();
      } else if (result.nothingToArchive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Everything is already archived!'),
            backgroundColor: Colors.blue,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive completed with errors:\n${result.errors.join("\n")}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archive failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  String _formatDateTime(DateTime dt) {
    if (dt.year == 1970) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Node Types'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: NodeType.values.map((type) {
            return CheckboxListTile(
              title: Text(type.name),
              value: _visibleTypes.contains(type),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _visibleTypes.add(type);
                  } else {
                    _visibleTypes.remove(type);
                  }
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
