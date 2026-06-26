import 'dart:async';

import 'package:flutter/material.dart';

class ClassicismSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearch;
  final String? hintText;

  const ClassicismSearchBar({
    super.key,
    required this.onSearch,
    this.hintText,
  });

  @override
  State<ClassicismSearchBar> createState() => _ClassicismSearchBarState();
}

class _ClassicismSearchBarState extends State<ClassicismSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.removeListener(() {});
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (value.trim().isNotEmpty) {
        widget.onSearch(value.trim());
      }
    });
  }

  void _onSubmitted(String value) {
    _debounce?.cancel();
    if (value.trim().isNotEmpty) {
      widget.onSearch(value.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      onSubmitted: _onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hintText ?? '搜索歌曲、歌单',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _controller.clear();
                  _onChanged('');
                },
              )
            : null,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}
