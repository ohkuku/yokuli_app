import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/models/kanban.dart';
import '../../../core/providers/kanban_provider.dart';

class KanbanScreen extends ConsumerStatefulWidget {
  const KanbanScreen({super.key});

  @override
  ConsumerState<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends ConsumerState<KanbanScreen> {
  @override
  Widget build(BuildContext context) {
    final kanban = ref.watch(kanbanProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          '船务看板',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: AppColors.cyan),
            tooltip: '添加列',
            onPressed: () => _showAddColumnDialog(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.modMaintenance,
        foregroundColor: AppColors.background,
        onPressed: () => _showCardSheet(context, null, null),
        child: const Icon(Icons.add_rounded),
      ),
      body: kanban.columns.isEmpty
          ? const Center(
              child: Text('暂无列', style: TextStyle(color: AppColors.textMuted)),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: kanban.columns.map((col) {
                  final cards = kanban.cardsForColumn(col.id);
                  return _KanbanColumnWidget(
                    column: col,
                    cards: cards,
                    allColumns: kanban.columns,
                    onAddCard: () => _showCardSheet(context, null, col.id),
                    onCardTap: (card) => _showCardSheet(context, card, null),
                    onDeleteColumn: () => _confirmDeleteColumn(context, col),
                  );
                }).toList(),
              ),
            ),
    );
  }

  Future<void> _showAddColumnDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('添加列', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '列名称',
            hintStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.cyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final title = ctrl.text.trim();
              Navigator.pop(ctx);
              if (title.isNotEmpty) {
                ref.read(kanbanProvider.notifier).addColumn(title);
              }
            },
            child: const Text('添加', style: TextStyle(color: AppColors.cyan)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteColumn(BuildContext context, KanbanColumn col) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('删除列', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '确认删除"${col.title}"列？其中的卡片将移至"待办"列。',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(kanbanProvider.notifier).deleteColumn(col.id);
    }
  }

  void _showCardSheet(BuildContext context, KanbanCard? card, String? defaultColumnId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CardSheet(
        card: card,
        defaultColumnId: defaultColumnId,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column widget
// ---------------------------------------------------------------------------

class _KanbanColumnWidget extends StatelessWidget {
  final KanbanColumn column;
  final List<KanbanCard> cards;
  final List<KanbanColumn> allColumns;
  final VoidCallback onAddCard;
  final ValueChanged<KanbanCard> onCardTap;
  final VoidCallback onDeleteColumn;

  const _KanbanColumnWidget({
    required this.column,
    required this.cards,
    required this.allColumns,
    required this.onAddCard,
    required this.onCardTap,
    required this.onDeleteColumn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Column header
          _ColumnHeader(
            column: column,
            cardCount: cards.length,
            onDelete: onDeleteColumn,
          ),
          // Cards list
          if (cards.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _KanbanCardWidget(
                  card: cards[i],
                  onTap: () => onCardTap(cards[i]),
                ),
              ),
            ),
          // Add card button
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加卡片', style: TextStyle(fontSize: 13)),
              onPressed: onAddCard,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final KanbanColumn column;
  final int cardCount;
  final VoidCallback onDelete;

  const _ColumnHeader({
    required this.column,
    required this.cardCount,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              column.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.inactive.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$cardCount',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                size: 16, color: AppColors.textMuted),
            color: AppColors.cardBg,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text('删除列', style: TextStyle(color: AppColors.danger)),
                ]),
              ),
            ],
            onSelected: (v) {
              if (v == 'delete') onDelete();
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card widget
// ---------------------------------------------------------------------------

class _KanbanCardWidget extends StatelessWidget {
  final KanbanCard card;
  final VoidCallback onTap;

  const _KanbanCardWidget({required this.card, required this.onTap});

  Color _priorityColor() {
    return switch (card.priority) {
      KanbanPriority.high => AppColors.danger,
      KanbanPriority.medium => AppColors.warning,
      KanbanPriority.low => AppColors.inactive,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    card.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                // Category chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    card.category,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            // Priority dot (top-right)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _priorityColor(),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card edit/create bottom sheet
// ---------------------------------------------------------------------------

class _CardSheet extends ConsumerStatefulWidget {
  final KanbanCard? card;
  final String? defaultColumnId;

  const _CardSheet({this.card, this.defaultColumnId});

  @override
  ConsumerState<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends ConsumerState<_CardSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late String _category;
  late KanbanPriority _priority;
  late String? _columnId;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _titleCtrl = TextEditingController(text: card?.title ?? '');
    _descCtrl = TextEditingController(text: card?.description ?? '');
    _category = card?.category ?? kKanbanDefaultCategories.last;
    _priority = card?.priority ?? KanbanPriority.medium;
    _columnId = card?.columnId ?? widget.defaultColumnId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题')),
      );
      return;
    }

    final kanban = ref.read(kanbanProvider);
    final columns = kanban.columns;
    final targetColumnId = _columnId ?? (columns.isNotEmpty ? columns.first.id : 'backlog');

    final notifier = ref.read(kanbanProvider.notifier);
    if (widget.card == null) {
      await notifier.addCard(KanbanCard(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        columnId: targetColumnId,
        title: title,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        category: _category,
        priority: _priority,
        createdAt: DateTime.now(),
      ));
    } else {
      await notifier.updateCard(widget.card!.copyWith(
        title: title,
        columnId: targetColumnId,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        category: _category,
        priority: _priority,
        updatedAt: DateTime.now(),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (widget.card == null) return;
    await ref.read(kanbanProvider.notifier).deleteCard(widget.card!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kanban = ref.watch(kanbanProvider);
    final columns = kanban.columns;

    // Ensure _columnId is valid
    if (_columnId == null && columns.isNotEmpty) {
      _columnId = columns.first.id;
    }
    final validColumnId =
        columns.any((c) => c.id == _columnId) ? _columnId : (columns.isNotEmpty ? columns.first.id : null);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.inactive,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Text(
                widget.card == null ? '新建卡片' : '编辑卡片',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),

              // Title field
              _FieldLabel('标题 *'),
              const SizedBox(height: 6),
              _inputField(
                controller: _titleCtrl,
                hint: '卡片标题',
              ),
              const SizedBox(height: 16),

              // Column selector
              if (columns.isNotEmpty) ...[
                _FieldLabel('列'),
                const SizedBox(height: 6),
                _DropdownContainer(
                  child: DropdownButton<String>(
                    value: validColumnId,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: AppColors.cardBg,
                    style: const TextStyle(color: AppColors.textPrimary),
                    items: columns.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.title),
                        )).toList(),
                    onChanged: (v) => setState(() => _columnId = v),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Category selector
              _FieldLabel('分类'),
              const SizedBox(height: 6),
              _DropdownContainer(
                child: DropdownButton<String>(
                  value: kKanbanDefaultCategories.contains(_category)
                      ? _category
                      : kKanbanDefaultCategories.last,
                  isExpanded: true,
                  underline: const SizedBox(),
                  dropdownColor: AppColors.cardBg,
                  style: const TextStyle(color: AppColors.textPrimary),
                  items: kKanbanDefaultCategories.map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      )).toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
              ),
              const SizedBox(height: 16),

              // Priority selector
              _FieldLabel('优先级'),
              const SizedBox(height: 6),
              _DropdownContainer(
                child: DropdownButton<KanbanPriority>(
                  value: _priority,
                  isExpanded: true,
                  underline: const SizedBox(),
                  dropdownColor: AppColors.cardBg,
                  style: const TextStyle(color: AppColors.textPrimary),
                  items: const [
                    DropdownMenuItem(
                        value: KanbanPriority.low,
                        child: Row(children: [
                          Icon(Icons.circle, size: 10, color: AppColors.inactive),
                          SizedBox(width: 8),
                          Text('低'),
                        ])),
                    DropdownMenuItem(
                        value: KanbanPriority.medium,
                        child: Row(children: [
                          Icon(Icons.circle, size: 10, color: AppColors.warning),
                          SizedBox(width: 8),
                          Text('中'),
                        ])),
                    DropdownMenuItem(
                        value: KanbanPriority.high,
                        child: Row(children: [
                          Icon(Icons.circle, size: 10, color: AppColors.danger),
                          SizedBox(width: 8),
                          Text('高'),
                        ])),
                  ],
                  onChanged: (v) => setState(() => _priority = v!),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              _FieldLabel('备注（可选）'),
              const SizedBox(height: 6),
              _inputField(
                controller: _descCtrl,
                hint: '详细描述...',
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _save,
                  child: const Text('保存',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),

              // Delete button (edit mode only)
              if (widget.card != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _delete,
                    child: const Text('删除卡片',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textMuted),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _DropdownContainer extends StatelessWidget {
  final Widget child;
  const _DropdownContainer({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}
