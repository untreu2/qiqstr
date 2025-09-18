import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../screens/thread_page.dart';
import '../theme/theme_manager.dart';
import '../providers/notes_list_provider.dart';
import '../providers/user_provider.dart';

class GridViewWidget extends StatefulWidget {
  const GridViewWidget({super.key});

  @override
  State<GridViewWidget> createState() => _GridViewWidgetState();
}

class _GridViewWidgetState extends State<GridViewWidget> with AutomaticKeepAliveClientMixin<GridViewWidget> {
  @override
  bool get wantKeepAlive => true;

  bool _isVideoUrl(String url) {
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.mp4') ||
        lowercaseUrl.endsWith('.mov') ||
        lowercaseUrl.endsWith('.mkv') ||
        lowercaseUrl.endsWith('.avi') ||
        lowercaseUrl.endsWith('.webm');
  }

  void _navigateToThread(BuildContext context, NoteModel note, DataService dataService) {
    final String rootIdToShow = (note.isReply && note.rootId != null && note.rootId!.isNotEmpty) ? note.rootId! : note.id;
    final String? focusedNoteId = (note.isReply && rootIdToShow != note.id) ? note.id : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadPage(
          rootNoteId: rootIdToShow,
          dataService: dataService,
          focusedNoteId: focusedNoteId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Selector<NotesListProvider, ({List<dynamic> notes, DataService dataService, String currentUserNpub})>(
      selector: (_, provider) => (
        notes: provider.notes,
        dataService: provider.dataService,
        currentUserNpub: provider.currentUserNpub,
      ),
      builder: (context, data, child) {
        final notesWithMedia = data.notes.where((note) {
          final parsedContent = note.parsedContentLazy;
          final mediaUrls = parsedContent['mediaUrls'] as List<String>? ?? [];
          return mediaUrls.isNotEmpty || note.hasMedia || note.isVideo;
        }).toList();

        if (notesWithMedia.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 64,
                      color: Colors.white54,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No media found',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.all(8.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= notesWithMedia.length) return null;

                final note = notesWithMedia[index];
                final parsedContent = note.parsedContentLazy;
                final mediaUrls = parsedContent['mediaUrls'] as List<String>? ?? [];

                String? displayUrl;
                bool isVideo = false;

                if (mediaUrls.isNotEmpty) {
                  displayUrl = mediaUrls.first;
                  isVideo = _isVideoUrl(displayUrl);
                } else if (note.isVideo && note.videoUrl != null) {
                  displayUrl = note.videoUrl!;
                  isVideo = true;
                }

                if (displayUrl == null) return const SizedBox.shrink();

                return _GridMediaItem(
                  note: note,
                  mediaUrl: displayUrl,
                  isVideo: isVideo,
                  dataService: data.dataService,
                  onTap: () => _navigateToThread(context, note, data.dataService),
                );
              },
              childCount: notesWithMedia.length,
            ),
          ),
        );
      },
    );
  }
}

class _GridMediaItem extends StatelessWidget {
  final NoteModel note;
  final String mediaUrl;
  final bool isVideo;
  final DataService dataService;
  final VoidCallback onTap;

  const _GridMediaItem({
    required this.note,
    required this.mediaUrl,
    required this.isVideo,
    required this.dataService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.colors.border.withOpacity(0.3),
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Positioned.fill(
                child: isVideo
                    ? _buildVideoThumbnailWithProfile(context)
                    : CachedNetworkImage(
                        imageUrl: mediaUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (context, url) => Container(
                          color: context.colors.surface,
                          child: Center(
                            child: Icon(
                              Icons.photo,
                              color: context.colors.textSecondary,
                              size: 24,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: context.colors.surface,
                          child: Center(
                            child: Icon(
                              Icons.broken_image,
                              color: context.colors.textSecondary,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
              ),
              if (isVideo)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: _buildMediaCountIndicator(context, note, isVideo),
              ),
              if (isVideo)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.videocam,
                          color: Colors.white,
                          size: 12,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'VIDEO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaCountIndicator(BuildContext context, NoteModel note, bool isVideo) {
    final parsedContent = note.parsedContentLazy;
    final mediaUrls = parsedContent['mediaUrls'] as List<String>? ?? [];

    if (mediaUrls.length <= 1 || isVideo) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library,
            color: Colors.white,
            size: 12,
          ),
          const SizedBox(width: 2),
          Text(
            '${mediaUrls.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoThumbnailWithProfile(BuildContext context) {
    final user = UserProvider.instance.getUserOrDefault(note.author);

    return CachedNetworkImage(
      imageUrl: user.profileImage,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (context, url) => Container(
        color: context.colors.surface,
        child: Center(
          child: Icon(
            Icons.video_library,
            color: context.colors.textSecondary,
            size: 32,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: context.colors.surface,
        child: Center(
          child: Icon(
            Icons.video_library,
            color: context.colors.textSecondary,
            size: 32,
          ),
        ),
      ),
    );
  }
}
