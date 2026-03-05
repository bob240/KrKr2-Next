import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../models/game_info.dart';
import '../models/game_metadata_candidate.dart';
import '../services/game_manager.dart';
import '../services/game_metadata_scraper.dart';
import '../utils/xp3_utils.dart';
import 'scrape_select_page.dart';

class GameDetailResult {
  final bool needsRefresh;
  final bool removed;
  final bool shouldLaunch;

  const GameDetailResult({
    this.needsRefresh = false,
    this.removed = false,
    this.shouldLaunch = false,
  });
}

class GameDetailPage extends StatefulWidget {
  const GameDetailPage({
    super.key,
    required this.game,
    required this.gameManager,
  });

  final GameInfo game;
  final GameManager gameManager;

  @override
  State<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends State<GameDetailPage> {
  bool _changed = false;
  final GameMetadataScraper _scraper = GameMetadataScraper();

  GameInfo get game => widget.game;
  GameManager get gm => widget.gameManager;
  bool get _isXp3 => game.path.toLowerCase().endsWith('.xp3');
  bool get _hasCover =>
      game.coverPath != null && File(game.coverPath!).existsSync();

  void _pop({bool removed = false}) {
    Navigator.of(context).pop(
      GameDetailResult(needsRefresh: _changed || removed, removed: removed),
    );
  }

  Future<void> _setCover() async {
    final l10n = AppLocalizations.of(context)!;
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.coverFromGallery),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.coverFromCamera),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (game.coverPath != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text(l10n.coverRemove,
                    style: const TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    if (source == 'remove') {
      await gm.setCoverImage(game.path, null);
      _changed = true;
      if (mounted) setState(() {});
      return;
    }

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;

    final docDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${docDir.path}/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    final ext = image.path.split('.').last;
    final fileName =
        '${game.path.hashCode}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destPath = '${coversDir.path}/$fileName';
    await File(image.path).copy(destPath);

    if (game.coverPath != null) {
      try {
        final oldFile = File(game.coverPath!);
        if (await oldFile.exists()) await oldFile.delete();
      } catch (_) {}
    }

    await gm.setCoverImage(game.path, destPath);
    _changed = true;
    if (mounted) setState(() {});
  }

  Future<void> _rename() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: game.displayTitle);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameGame),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.displayTitle,
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName != null && newName.isNotEmpty && mounted) {
      await gm.renameGame(game.path, newName);
      _changed = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openScrape() async {
    final l10n = AppLocalizations.of(context)!;

    final keyword = await showDialog<String>(
      context: context,
      builder: (ctx) => _ScrapeSearchDialog(
        l10n: l10n,
        initialKeyword: game.displayTitle,
      ),
    );
    if (keyword == null || !mounted) return;
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.scrapeMetadataEnterName)),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l10n.scrapeMetadataSearch),
              ],
            ),
          ),
        ),
      ),
    );

    List<GameMetadataCandidate> candidates;
    try {
      candidates = await _scraper.search(trimmed);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.scrapeMetadataSourceError)),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // close loading dialog
    if (!mounted) return;
    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (ctx) => ScrapeSelectPage(
          candidates: candidates,
          game: game,
          gameManager: gm,
          scraper: _scraper,
        ),
      ),
    );
    if (applied == true && mounted) {
      _changed = true;
      setState(() {});
    }
  }

  Future<void> _packUnpack() async {
    final l10n = AppLocalizations.of(context)!;
    final isXp3 = _isXp3;

    final progress = ValueNotifier<double>(0.0);
    final currentFile = ValueNotifier<String>('');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(isXp3 ? l10n.unpackingProgress : l10n.packingProgress),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, __) =>
                    LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: currentFile,
                builder: (_, value, __) => Text(
                  value,
                  style: Theme.of(ctx).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      if (isXp3) {
        final destDir = p.join(
          p.dirname(game.path),
          p.basenameWithoutExtension(game.path),
        );
        await xp3Extract(game.path, destDir, onProgress: (prog, file) {
          progress.value = prog;
          currentFile.value = file;
        });
        if (mounted) {
          Navigator.of(context).pop();
          final newGame = GameInfo(path: destDir);
          await gm.addGame(newGame);
          _changed = true;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.unpackComplete),
            behavior: SnackBarBehavior.floating,
          ));
        }
      } else {
        final xp3Path = '${game.path}.xp3';
        await xp3Pack(game.path, xp3Path, onProgress: (prog, file) {
          progress.value = prog;
          currentFile.value = file;
        });
        if (mounted) {
          Navigator.of(context).pop();
          final newGame = GameInfo(path: xp3Path);
          await gm.addGame(newGame);
          _changed = true;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.packComplete),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.xp3OperationFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      progress.dispose();
      currentFile.dispose();
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removeGame),
        content: Text(l10n.removeGameConfirm(game.displayTitle)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await gm.removeGame(game.path);
      _pop(removed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop();
      },
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            _buildCoverAppBar(colorScheme),
            SliverToBoxAdapter(child: _buildInfoSection(l10n, textTheme, colorScheme)),
            SliverToBoxAdapter(child: _buildLaunchButton(l10n)),
            SliverToBoxAdapter(child: _buildManageSection(l10n, colorScheme)),
            SliverToBoxAdapter(child: _buildDangerSection(l10n, colorScheme)),
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverAppBar(ColorScheme colorScheme) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _pop,
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (_hasCover)
              Image.file(
                File(game.coverPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholderBar(colorScheme),
              )
            else
              _buildPlaceholderBar(colorScheme),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.3, 1.0],
                  colors: [
                    Colors.black38,
                    Colors.transparent,
                    Colors.black26,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.image_outlined),
          tooltip: AppLocalizations.of(context)!.setCover,
          onPressed: _setCover,
        ),
      ],
    );
  }

  Widget _buildPlaceholderBar(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surfaceContainerHigh,
            colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.videogame_asset,
          size: 72,
          color: colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildInfoSection(
      AppLocalizations l10n, TextTheme textTheme, ColorScheme colorScheme) {
    final lastPlayed = game.lastPlayed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            game.displayTitle,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _infoRow(
            Icons.folder_outlined,
            game.path,
            colorScheme,
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: game.path));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.copiedToClipboard),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          if (lastPlayed != null) ...[
            const SizedBox(height: 8),
            _infoRow(
              Icons.schedule,
              l10n.lastPlayed(_formatDate(lastPlayed, l10n)),
              colorScheme,
            ),
          ],
          if ((game.playDurationSeconds ?? 0) >= 60) ...[
            const SizedBox(height: 8),
            _infoRow(
              Icons.timer_outlined,
              l10n.playDuration(GameInfo.formatPlayDuration(game.playDurationSeconds!)),
              colorScheme,
            ),
          ],
          const SizedBox(height: 8),
          _infoRow(
            Icons.inventory_2_outlined,
            _isXp3 ? 'XP3 Archive' : 'Directory',
            colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, ColorScheme colorScheme,
      {VoidCallback? onLongPress}) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchButton(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: FilledButton.icon(
        onPressed: () {
          gm.markPlayed(game.path);
          Navigator.of(context).pop(
            const GameDetailResult(needsRefresh: true, shouldLaunch: true),
          );
        },
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(l10n.launchGame),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildManageSection(AppLocalizations l10n, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.setCover),
              trailing: const Icon(Icons.chevron_right),
              onTap: _setCover,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.rename),
              trailing: const Icon(Icons.chevron_right),
              onTap: _rename,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: Text(l10n.scrapeMetadata),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openScrape,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: Icon(_isXp3 ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(_isXp3 ? l10n.unpackXp3 : l10n.packXp3),
              trailing: const Icon(Icons.chevron_right),
              onTap: _packUnpack,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerSection(AppLocalizations l10n, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(Icons.delete_outline, color: colorScheme.error),
          title: Text(l10n.remove, style: TextStyle(color: colorScheme.error)),
          trailing: Icon(Icons.chevron_right, color: colorScheme.error),
          onTap: _remove,
        ),
      ),
    );
  }

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.hoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.daysAgo(diff.inDays);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Step 1 dialog: enter game name and search. Owns its TextEditingController
/// so it is disposed when the dialog is disposed.
class _ScrapeSearchDialog extends StatefulWidget {
  const _ScrapeSearchDialog({
    required this.l10n,
    required this.initialKeyword,
  });

  final AppLocalizations l10n;
  final String initialKeyword;

  @override
  State<_ScrapeSearchDialog> createState() => _ScrapeSearchDialogState();
}

class _ScrapeSearchDialogState extends State<_ScrapeSearchDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKeyword);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AlertDialog(
      title: Text(l10n.scrapeMetadataDialogTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: l10n.scrapeMetadataSearchHint,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.scrapeMetadataSearch),
        ),
      ],
    );
  }
}
