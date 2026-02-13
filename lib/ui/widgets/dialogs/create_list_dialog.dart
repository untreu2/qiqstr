import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';
import '../user/user_tile_widget.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/user_search/user_search_bloc.dart';
import '../../../presentation/blocs/user_search/user_search_event.dart';
import '../../../presentation/blocs/user_search/user_search_state.dart';
import '../../../l10n/app_localizations.dart';

Future<Map<String, dynamic>?> showCreateListDialog({
  required BuildContext context,
}) async {
  final colors = context.colors;

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => const _CreateListDialogContent(),
  );
}

class _CreateListDialogContent extends StatefulWidget {
  const _CreateListDialogContent();

  @override
  State<_CreateListDialogContent> createState() =>
      _CreateListDialogContentState();
}

class _CreateListDialogContentState extends State<_CreateListDialogContent> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _searchController = TextEditingController();
  late final UserSearchBloc _searchBloc;
  final _selectedUsers = <String, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    _searchBloc = AppDI.get<UserSearchBloc>();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _searchController.dispose();
    _searchBloc.close();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchBloc.add(UserSearchQueryChanged(query));
  }

  void _toggleUser(Map<String, dynamic> user) {
    final pubkey = user['pubkeyHex'] as String? ?? '';
    if (pubkey.isEmpty) return;

    setState(() {
      if (_selectedUsers.containsKey(pubkey)) {
        _selectedUsers.remove(pubkey);
      } else {
        _selectedUsers[pubkey] = user;
      }
    });
  }

  void _onCreate() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    Navigator.pop(context, {
      'title': title,
      'description': _descController.text.trim(),
      'pubkeys': _selectedUsers.keys.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return BlocProvider<UserSearchBloc>.value(
      value: _searchBloc,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 40,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.createList,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              CustomInputField(
                controller: _titleController,
                hintText: l10n.listNameHint,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              CustomInputField(
                controller: _descController,
                hintText: l10n.listDescriptionHint,
              ),
              const SizedBox(height: 16),
              if (_selectedUsers.isNotEmpty) ...[
                _buildSelectedUsers(colors),
                const SizedBox(height: 12),
              ],
              CustomInputField(
                controller: _searchController,
                hintText: l10n.searchUsers,
                onChanged: _onSearchChanged,
                prefixIcon: Icon(
                  Icons.search,
                  color: colors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: BlocBuilder<UserSearchBloc, UserSearchState>(
                  builder: (context, state) {
                    if (state is UserSearchLoaded &&
                        state.filteredUsers.isNotEmpty) {
                      return ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: state.filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = state.filteredUsers[index];
                          final pubkey =
                              user['pubkeyHex'] as String? ?? '';
                          final isSelected =
                              _selectedUsers.containsKey(pubkey);

                          return UserTile(
                            user: user,
                            showFollowButton: false,
                            showSelectionIndicator: true,
                            isSelected: isSelected,
                            onTap: () => _toggleUser(user),
                          );
                        },
                      );
                    }
                    if (state is UserSearchLoaded && state.isSearching) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          color: colors.textPrimary,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: l10n.cancel,
                      onPressed: () => Navigator.pop(context),
                      size: ButtonSize.large,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SecondaryButton(
                      label: l10n.create,
                      onPressed: _onCreate,
                      size: ButtonSize.large,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedUsers(dynamic colors) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedUsers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = _selectedUsers.entries.elementAt(index);
          final user = entry.value;
          final name = user['name'] as String? ?? '';
          final picture = user['profileImage'] as String? ?? '';

          return GestureDetector(
            onTap: () => _toggleUser(user),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.overlayLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (picture.isNotEmpty)
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: NetworkImage(picture),
                      backgroundColor: Colors.grey.shade800,
                    )
                  else
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.grey.shade800,
                      child: Icon(
                        Icons.person,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    name.length > 12 ? '${name.substring(0, 12)}...' : name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.close,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
