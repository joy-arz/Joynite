#!/usr/bin/env python3
"""Keep native and shared offline metadata generated from the same catalog."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'desktop/src-tauri/publishers.json'
TARGET = ROOT / 'macos/Sources/JoyniteCore/PublisherCatalog.swift'

def rendered():
    entries = json.loads(SOURCE.read_text(encoding='utf-8'))
    ids, aliases = set(), set()
    def quote(value):
        return json.dumps(value, ensure_ascii=False)
    rows = []
    for item in entries:
        if item['id'] in ids or not item['aliases'] or not item['summary'] or not item['developer']:
            raise ValueError('Incomplete or duplicate catalog entry: ' + item['id'])
        ids.add(item['id'])
        for alias in item['aliases']:
            normalized = ''.join(c for c in alias.casefold() if c.isalnum())
            # Case/punctuation variants within one game are harmless; cross-game collisions are not.
            key = (normalized, item['id'])
            if any(a == normalized and owner != item['id'] for a, owner in aliases):
                raise ValueError('Ambiguous game alias: ' + alias)
            aliases.add(key)
        for key in ['url', 'artwork', 'background']:
            if item.get(key) and not item[key].startswith('https://'):
                raise ValueError('Catalog URLs must use HTTPS: ' + item['id'])
        fields = ', '.join(f'{key}: {quote(item.get(key, ""))}' for key in ['name', 'summary', 'developer', 'artwork', 'url', 'source'])
        fields += ', genres: [' + ', '.join(map(quote, item['genres'])) + '], background: ' + quote(item.get('background', ''))
        rows.append('        .init(id: ' + quote(item['id']) + ', aliases: [' + ', '.join(map(quote, item['aliases'])) + '], metadata: .init(' + fields + '))')
    return '''import Foundation

// Generated from desktop/src-tauri/publishers.json by scripts/sync-publisher-catalog.py.
public struct PublisherGame: Identifiable, Sendable {
    public let id: String
    public let aliases: [String]
    public let metadata: Metadata
}
public enum PublisherCatalog {
    public static let games: [PublisherGame] = [
''' + ',\n'.join(rows) + '''
    ]
    public static func match(_ name: String) -> PublisherGame? {
        let normalized = Game.normalized(name)
        return games.first { $0.aliases.contains { Game.normalized($0) == normalized } }
    }
}
'''

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    expected = rendered()
    if args.write:
        TARGET.write_text(expected, encoding='utf-8')
    elif TARGET.read_text(encoding='utf-8') != expected:
        raise SystemExit('Native catalog is out of sync. Run python3 scripts/sync-publisher-catalog.py --write')
    print('Native/shared publisher catalogs match.')
