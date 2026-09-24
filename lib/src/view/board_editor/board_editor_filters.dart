import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/board_editor/board_editor_controller.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/widgets/adaptive_bottom_sheet.dart';
import 'package:dartchess/dartchess.dart' hide Position;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class BoardEditorFilters extends ConsumerWidget {
  const BoardEditorFilters({required this.params, super.key});

  final BoardEditorControllerParams? params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final srs = SrsTheme.maybeOf(context);
    final editorController = boardEditorControllerProvider(params);
    final editorState = ref.watch(editorController);

    final castlingSide = Side.values
        .where((side) => editorState.variant.sideCanCastle(side))
        .toIList();

    Widget buildChip({
      required String label,
      required bool selected,
      required ValueChanged<bool>? onSelected,
    }) {
      final fg = selected
          ? (srs?.ground ?? ColorScheme.of(context).onPrimary)
          : (srs?.ink ?? ColorScheme.of(context).onSurface);
      final bg = selected
          ? (srs?.ink ?? ColorScheme.of(context).primary)
          : (srs?.surface ?? ColorScheme.of(context).surface);
      final border = selected
          ? BorderSide.none
          : BorderSide(color: srs?.hairline ?? Theme.of(context).dividerColor);

      return ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        selected: selected,
        onSelected: onSelected,
        selectedColor: srs?.ink ?? ColorScheme.of(context).primary,
        backgroundColor: bg,
        side: border,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        showCheckmark: false,
      );
    }

    return BottomSheetScrollableContainer(
      padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Text(
            'Side to move',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: srs?.ink2 ?? ColorScheme.of(context).onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Wrap(
            spacing: 8.0,
            children: Side.values.map((side) {
              return buildChip(
                label: side == Side.white ? context.l10n.whitePlays : context.l10n.blackPlays,
                selected: editorState.sideToPlay == side,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(editorController.notifier).setSideToPlay(side);
                  }
                },
              );
            }).toList(),
          ),
        ),
        if (castlingSide.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Text(
              context.l10n.castling,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: srs?.ink2 ?? ColorScheme.of(context).onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...Side.values.where((side) => editorState.variant.sideCanCastle(side)).map((side) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 80.0,
                    child: Text(
                      side == Side.white ? context.l10n.white : context.l10n.black,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: srs?.ink ?? ColorScheme.of(context).onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...[CastlingSide.king, CastlingSide.queen].map((cSide) {
                    final isPossible = editorState.isCastlingPossible(side, cSide);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: buildChip(
                        label: cSide == CastlingSide.king ? 'O-O' : 'O-O-O',
                        selected: isPossible && editorState.isCastlingAllowed(side, cSide),
                        onSelected: isPossible
                            ? (selected) {
                                ref
                                    .read(editorController.notifier)
                                    .setCastling(side, cSide, selected);
                              }
                            : null,
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
        if (editorState.variant.hasEnPassant && editorState.enPassantOptions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Text(
              'En passant',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: srs?.ink2 ?? ColorScheme.of(context).onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Wrap(
              spacing: 8.0,
              children: editorState.enPassantOptions.squares.map((square) {
                return buildChip(
                  label: square.name,
                  selected: editorState.enPassantSquare == square,
                  onSelected: (selected) {
                    ref.read(editorController.notifier).toggleEnPassantSquare(square);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
