"""把 StoryAura/Danbooru-Dataset-csv 精简成程序内置的词库 assets/danbooru_tags.tsv.gz。

用法(在项目根目录):
    python tool/make_tag_dict.py <放着两个 CSV 的文件夹>

需要的两个文件从 https://huggingface.co/datasets/StoryAura/Danbooru-Dataset-csv 下载:
    danbooru_dataset_general_260820.csv  通用标签
    danbooru_character_tags.csv          角色标签

每行输出「标签 \t 使用次数 \t 中文含义」,按使用次数从多到少排。
太冷门的不收(通用标签少于 20 张图、角色少于 50 张图),这样文件只有 2 MB 左右。
"""

import csv
import gzip
import io
import os
import sys
from typing import Callable, Iterator

GENERAL = 'danbooru_dataset_general_260820.csv'
CHARACTER = 'danbooru_character_tags.csv'
MIN_GENERAL = 20
MIN_CHARACTER = 50
MAX_ZH = 100


def clean(text: str) -> str:
    return ' '.join(text.replace('\t', ' ').split())[:MAX_ZH]


def rows(path: str, tag_column: str, minimum: int, zh: Callable[[dict], str]) -> Iterator[tuple[str, int, str]]:
    with io.open(path, encoding='utf-8-sig', newline='') as f:
        for row in csv.DictReader(f):
            try:
                count = int(float(row['post_count'] or 0))
            except ValueError:
                continue  # 表里有几行错了位,数量那一列不是数字
            tag = row[tag_column].strip()
            if tag and count >= minimum:
                yield tag, count, clean(zh(row))


def main(folder: str) -> None:
    best = {}
    sources = [
        (GENERAL, 'tag', MIN_GENERAL, lambda r: r['other_names']),
        (CHARACTER, 'character_tag', MIN_CHARACTER,
         lambda r: r['other_names'] + ' ' + r['copyright']),
    ]
    for name, column, minimum, zh in sources:
        for tag, count, meaning in rows(os.path.join(folder, name), column, minimum, zh):
            if tag not in best or best[tag][0] < count:
                best[tag] = (count, meaning)
    ordered = sorted(best.items(), key=lambda kv: -kv[1][0])
    text = '\n'.join(f'{tag}\t{count}\t{zh}' for tag, (count, zh) in ordered)
    out = os.path.join('assets', 'danbooru_tags.tsv.gz')
    with io.open(out, 'wb') as f:
        f.write(gzip.compress(text.encode('utf-8'), 9))
    print(len(ordered), 'tags ->', out, round(os.path.getsize(out) / 1e6, 2), 'MB')


if __name__ == '__main__':
    main(sys.argv[1])
