/// Graph Canvas - Custom painter for knowledge graph visualization
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../models/knowledge_node.dart';

class GraphCanvas extends StatelessWidget {
  final KnowledgeGraph graph;
  final KnowledgeNode? selectedNode;
  final Set<String> highlightedNodeIds;
  final Set<NodeType> visibleTypes;
  final Function(KnowledgeNode) onNodeTap;

  const GraphCanvas({
    super.key,
    required this.graph,
    this.selectedNode,
    this.highlightedNodeIds = const {},
    required this.visibleTypes,
    required this.onNodeTap,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(2000, 2000), // Large canvas for the graph
      painter: GraphPainter(
        graph: graph,
        selectedNode: selectedNode,
        highlightedNodeIds: highlightedNodeIds,
        visibleTypes: visibleTypes,
      ),
      child: GestureDetector(
        onTapUp: (details) {
          // Check if tap hits any node
          final RenderBox box = context.findRenderObject() as RenderBox;
          final localPosition = box.globalToLocal(details.globalPosition);
          
          for (final node in graph.nodes) {
            if (!visibleTypes.contains(node.type)) continue;
            
            final dx = localPosition.dx - node.x;
            final dy = localPosition.dy - node.y;
            final distance = sqrt(dx * dx + dy * dy);
            
            if (distance < node.size + 5) {
              onNodeTap(node);
              return;
            }
          }
        },
      ),
    );
  }
}

class GraphPainter extends CustomPainter {
  final KnowledgeGraph graph;
  final KnowledgeNode? selectedNode;
  final Set<String> highlightedNodeIds;
  final Set<NodeType> visibleTypes;

  GraphPainter({
    required this.graph,
    this.selectedNode,
    required this.highlightedNodeIds,
    required this.visibleTypes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Safety check: ensure graph has nodes
    if (graph.nodes.isEmpty) {
      // Draw "No data" message
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'No nodes to display',
          style: TextStyle(color: Colors.white38, fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      textPainter.paint(
        canvas,
        Offset(size.width / 2 - textPainter.width / 2, size.height / 2),
      );
      return;
    }
    
    // 1. Draw edges first (behind nodes)
    _drawEdges(canvas);
    
    // 2. Draw nodes
    _drawNodes(canvas);
    
    // 3. Draw labels
    _drawLabels(canvas);
  }

  void _drawEdges(Canvas canvas) {
    for (final edge in graph.edges) {
      final fromNode = graph.getNode(edge.fromId);
      final toNode = graph.getNode(edge.toId);
      
      if (fromNode == null || toNode == null) continue;
      
      // Skip if either node type is filtered out
      if (!visibleTypes.contains(fromNode.type) || 
          !visibleTypes.contains(toNode.type)) {
        continue;
      }
      
      // Highlight edges connected to selected node
      final isHighlighted = highlightedNodeIds.contains(fromNode.id) && 
                           highlightedNodeIds.contains(toNode.id);
      
      final paint = Paint()
        ..color = isHighlighted 
            ? edge.color.withOpacity(0.8) 
            : edge.color.withOpacity(0.2)
        ..strokeWidth = isHighlighted ? edge.thickness * 2 : edge.thickness
        ..style = PaintingStyle.stroke;
      
      canvas.drawLine(
        Offset(fromNode.x, fromNode.y),
        Offset(toNode.x, toNode.y),
        paint,
      );
    }
  }

  void _drawNodes(Canvas canvas) {
    for (final node in graph.nodes) {
      if (!visibleTypes.contains(node.type)) continue;
      
      final isSelected = selectedNode?.id == node.id;
      final isHighlighted = highlightedNodeIds.contains(node.id);
      final isDimmed = highlightedNodeIds.isNotEmpty && !isHighlighted;
      
      // Outer glow for selected node
      if (isSelected) {
        final glowPaint = Paint()
          ..color = node.color.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
        canvas.drawCircle(
          Offset(node.x, node.y),
          node.size + 10,
          glowPaint,
        );
      }
      
      // Node circle
      final nodePaint = Paint()
        ..color = isDimmed 
            ? node.color.withOpacity(0.2) 
            : node.color.withOpacity(isHighlighted ? 1.0 : 0.7)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(node.x, node.y),
        node.size,
        nodePaint,
      );
      
      // Border for selected node
      if (isSelected) {
        final borderPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(
          Offset(node.x, node.y),
          node.size + 2,
          borderPaint,
        );
      }
    }
  }

  void _drawLabels(Canvas canvas) {
    for (final node in graph.nodes) {
      if (!visibleTypes.contains(node.type)) continue;
      
      final isHighlighted = highlightedNodeIds.contains(node.id);
      final isDimmed = highlightedNodeIds.isNotEmpty && !isHighlighted;
      
      // Only show labels for highlighted nodes or if nothing is selected
      if (isDimmed && highlightedNodeIds.isNotEmpty) continue;
      
      final textStyle = TextStyle(
        color: isDimmed 
            ? Colors.white24 
            : Colors.white.withOpacity(isHighlighted ? 1.0 : 0.7),
        fontSize: isHighlighted ? 12 : 10,
        fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
      );
      
      final textSpan = TextSpan(
        text: node.label,
        style: textStyle,
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      
      // Position label below node
      final labelOffset = Offset(
        node.x - textPainter.width / 2,
        node.y + node.size + 8,
      );
      
      // Draw text background for better readability
      if (isHighlighted) {
        final bgPaint = Paint()
          ..color = Colors.black.withOpacity(0.7)
          ..style = PaintingStyle.fill;
        
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            labelOffset.dx - 4,
            labelOffset.dy - 2,
            textPainter.width + 8,
            textPainter.height + 4,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(bgRect, bgPaint);
      }
      
      textPainter.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(GraphPainter oldDelegate) {
    return graph != oldDelegate.graph ||
           selectedNode != oldDelegate.selectedNode ||
           highlightedNodeIds != oldDelegate.highlightedNodeIds ||
           visibleTypes != oldDelegate.visibleTypes;
  }
}
