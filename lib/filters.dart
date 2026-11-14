import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'ui.dart';

class FiltersDialog extends StatefulWidget {
  final Api api;
  final Json initial;
  const FiltersDialog({super.key, required this.api, required this.initial});
  @override
  State<FiltersDialog> createState() => _FiltersState();
}

class _FiltersState extends State<FiltersDialog> {
  late Json filters;
  String? validationError;
  final fields = <String, TextEditingController>{};
  late Future<List<dynamic>> dictionaries;
  static const numeric = {
    'greater_year': 'Год от',
    'lesser_year': 'Год до',
    'greater_shikimori_rating': 'Рейтинг от',
    'lesser_shikimori_rating': 'Рейтинг до',
    'greater_episodes_total': 'Серий от',
    'lesser_episodes_total': 'Серий до',
    'greater_shikimori_votes': 'Оценок от',
    'lesser_shikimori_votes': 'Оценок до',
  };
  @override
  void initState() {
    super.initState();
    filters = Map.of(widget.initial);
    for (final k in numeric.keys) {
      fields[k] = TextEditingController(text: '${filters[k] ?? ''}');
    }
    dictionaries = Future.wait([
      widget.api.request('/api/anime/genres', query: {'limit': 500}),
      widget.api.request(
        '/api/anime/studios',
        query: {'limit': 2000, 'offset': 0},
      ),
    ]);
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> values(String key) => filters[key] is List
      ? (filters[key] as List).map((v) => '$v').toList()
      : filters[key] == null
      ? []
      : ['${filters[key]}'];
  Widget choices(String name, String key, Map<String, String> options) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.entries
                .map(
                  (e) => labelButton(
                    e.value,
                    () {
                      setState(() {
                        final v = values(key);
                        v.contains(e.key) ? v.remove(e.key) : v.add(e.key);
                        if (v.isEmpty) {
                          filters.remove(key);
                        } else {
                          filters[key] = v;
                        }
                      });
                    },
                    selected: values(key).contains(e.key),
                    autofocus: key == 'anime_kind' && e.key == 'tv',
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],
      );
  Future<void> selectNames(String key, String title, List<String> all) async {
    final selected = values(key).toSet();
    var search = '';
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 650,
            height: 430,
            child: Column(
              children: [
                TvTextEntry(
                  label: 'Поиск',
                  value: search,
                  onChanged: (v) => update(() => search = v.toLowerCase()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: all
                        .where((s) => s.toLowerCase().contains(search))
                        .map(
                          (name) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TvButton(
                              autofocus:
                                  name ==
                                  (selected.isEmpty
                                      ? all.firstOrNull
                                      : selected.first),
                              selected: selected.contains(name),
                              onPressed: () => update(() {
                                selected.contains(name)
                                    ? selected.remove(name)
                                    : selected.add(name);
                              }),
                              child: Row(
                                children: [
                                  Icon(
                                    selected.contains(name)
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(name)),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            labelButton('Готово', () {
              setState(() {
                if (selected.isEmpty) {
                  filters.remove(key);
                } else {
                  filters[key] = selected.toList();
                }
              });
              Navigator.pop(d);
            }, icon: Icons.check_rounded),
          ],
        ),
      ),
    );
  }

  static const orderOptions = {
    '[["shikimori_rating","DESC NULLS LAST"]]': 'Рейтинг: сначала лучшие',
    '[["shikimori_votes","DESC NULLS LAST"]]': 'Популярность',
    '[["year","DESC NULLS LAST"]]': 'Год: сначала новые',
    '[["year","ASC NULLS LAST"]]': 'Год: сначала старые',
    '[["episodes_total","DESC NULLS LAST"]]': 'Больше серий',
    'random': 'Случайно',
  };
  Future<void> selectOrder() async {
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Порядок'),
        content: SizedBox(
          width: 650,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in orderOptions.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: labelButton(
                      entry.value,
                      () => Navigator.pop(d, entry.key),
                      selected: filters['order'] == entry.key,
                      autofocus:
                          entry.key ==
                          (filters['order'] ?? orderOptions.keys.first),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [labelButton('Отмена', () => Navigator.pop(d))],
      ),
    );
    if (result != null && mounted) setState(() => filters['order'] = result);
  }

  void apply() {
    for (final e in fields.entries) {
      final value = num.tryParse(e.value.text.replaceAll(',', '.'));
      if (e.value.text.trim().isNotEmpty && value == null) {
        setState(() => validationError = 'Проверьте поле «${numeric[e.key]}»');
        return;
      }
      if (value != null) {
        filters[e.key] = value;
      } else {
        filters.remove(e.key);
      }
    }
    for (final pair in [
      ['greater_year', 'lesser_year'],
      ['greater_shikimori_rating', 'lesser_shikimori_rating'],
      ['greater_episodes_total', 'lesser_episodes_total'],
    ]) {
      if (filters[pair[0]] is num &&
          filters[pair[1]] is num &&
          filters[pair[0]] > filters[pair[1]]) {
        setState(
          () => validationError = 'Нижняя граница не должна превышать верхнюю',
        );
        return;
      }
    }
    Navigator.pop(context, filters);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Фильтры и сортировка'),
        if (validationError != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              validationError!,
              style: TextStyle(
                fontSize: 17,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    ),
    content: SizedBox(
      width: 850,
      height: 550,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            choices('Тип', 'anime_kind', {
              'tv': 'Сериал',
              'movie': 'Фильм',
              'ova': 'OVA',
              'ona': 'ONA',
              'special': 'Спешл',
              'music': 'Клип',
            }),
            choices('Статус', 'all_status', {
              'released': 'Вышел',
              'ongoing': 'Онгоинг',
              'anons': 'Анонс',
            }),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: fields.entries
                  .map(
                    (e) => SizedBox(
                      width: 185,
                      child: TvTextEntry(
                        label: numeric[e.key]!,
                        value: e.value.text,
                        numeric: true,
                        onChanged: (v) => setState(() => e.value.text = v),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            choices('Возрастной рейтинг', 'rating_mpaa', {
              'G': 'G',
              'PG': 'PG',
              'PG-13': 'PG-13',
              'R-17': 'R-17',
              'R+': 'R+',
              'Rx': 'Rx',
            }),
            LoadView(
              future: dictionaries,
              builder: (raw) {
                final genres = objects(raw[0])
                    .map((v) => '${v['name']}')
                    .toList();
                final studios = raw[1] is List
                    ? (raw[1] as List)
                          .map(
                            (v) =>
                                v is Map ? '${v['name'] ?? v['title']}' : '$v',
                          )
                          .toList()
                    : <String>[];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in {
                      'anime_genres': 'Жанры',
                      'exclude_anime_genres': 'Исключить жанры',
                      'anime_studios': 'Студии',
                      'exclude_anime_studios': 'Исключить студии',
                    }.entries)
                      labelButton(
                        '${entry.value}: ${values(entry.key).length}',
                        () => selectNames(
                          entry.key,
                          entry.value,
                          entry.key.contains('genres') ? genres : studios,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: labelButton(
                'Порядок: ${orderOptions[filters['order']] ?? 'Не выбран'}',
                selectOrder,
                icon: Icons.sort_rounded,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      labelButton(
        'Сбросить',
        () => Navigator.pop(context, <String, dynamic>{}),
      ),
      labelButton('Отмена', () => Navigator.pop(context)),
      labelButton('Применить', apply, icon: Icons.check_rounded),
    ],
  );
}
