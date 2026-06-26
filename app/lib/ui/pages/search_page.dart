import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../widgets/mini_player.dart';
import '../widgets/search_bar.dart';
import '../widgets/search_result_list.dart';

class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: ClassicismSearchBar(
          hintText: '搜索歌曲、歌单',
          onSearch: (query) {
            ref.read(searchProvider.notifier).search(query);
          },
        ),
      ),
      body: const SearchResultList(),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}
