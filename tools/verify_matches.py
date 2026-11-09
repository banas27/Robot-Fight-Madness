#!/usr/bin/env python3
"""Run real Godot matches without rendering and validate combat invariants.
Python standard library only. Headless tests do not validate video or appearance.
"""
import argparse
import json
import math
from pathlib import Path
import subprocess
import tempfile

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--count', type=int, default=10)
    parser.add_argument('--seeds', type=int, nargs='+')
    parser.add_argument('--output', type=Path, default=Path('qa/episode-pass/headless-results.json'))
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    cfg = json.loads((project / 'config/match.json').read_text())
    combat = json.loads((project / 'config/combat.json').read_text())
    episode = json.loads((project / 'config/presentation.json').read_text()).get('episode')
    summaries = []
    with tempfile.TemporaryDirectory(prefix='rfs-qa-') as temp:
        for seed in args.seeds or range(1, args.count + 1):
            path = Path(temp) / f'{seed}.json'
            result = subprocess.run([
                args.godot, '--headless', '--path', str(project), '--fixed-fps', '60',
                '--', '--autostop', f'--seed={seed}', f'--report={path}'
            ], capture_output=True, text=True, timeout=45)
            combined = result.stdout + result.stderr
            if result.returncode or 'ERROR:' in combined or not path.exists():
                raise RuntimeError(f'Seed {seed} failed:\n{combined}')
            data = json.loads(path.read_text())
            studio = data['version'] == 'R08'
            identity = data['version'] in ('R07', 'R08')
            solver = data['version'] in ('R03', 'R04', 'R05', 'R06') or identity
            components = data['version'] in ('R04', 'R05', 'R06') or identity
            names = ('Riptide', 'Bulldozer')
            maxima = [float(cfg['health'])] * 2
            if identity:
                names = (combat['saw']['name'], combat['drum']['name'])
                maxima = [float(combat[k]['max_hp']) for k in ('saw', 'drum')]
                assert data['max_hp'] == maxima, data
            assert data['winner'] in ('RIPTIDE', 'BULLDOZER', 'DRAW'), data
            fight_limit = episode['fight_seconds'] if studio else cfg['fight_seconds']
            intro = 2 * episode['intro_shot_seconds'] if studio else cfg['intro_seconds']
            if identity and not studio:
                intro = max(.5, min(6.0, float(combat['intro_seconds'])))
            assert 0 < data['fight_duration'] <= fight_limit + .1, data
            if studio:
                assert data['intro_duration'] == intro, data
                assert data['showcase_duration'] == episode['showcase_seconds'], data
                if data['reason'] == 'time limit / health decision':
                    assert data['fight_duration'] == fight_limit, data
            else:
                assert data['duration'] <= intro + fight_limit + cfg['result_seconds'] + .2, data
            assert len(data['events']) > 0, data
            assert all(0 <= hp <= maximum for hp, maximum in zip(data['hp'], maxima)), data
            assert data['max_arena_extent_ratio'] < 1.08, data
            hp = dict(zip(names, maxima))
            last_time = -1
            last_hit = {}
            for event in data['events']:
                assert event['time'] >= last_time, event
                last_time = event['time']
                target = names[1] if event['attacker'] == names[0] else names[0]
                hp[target] = max(0, hp[target] - event['damage'])
                assert abs(hp[target] - event['target_hp']) < .001, event
                if solver or data['version'] == 'R02':
                    kind = 'saw' if event['attacker'] == names[0] else 'drum'
                    base = combat[kind]['base_attack' if identity else 'hit_damage']
                    assert event['weapon'] == kind and 0 < event['damage'] <= base, event
                    if identity:
                        assert event['damage'] == math.floor(base * (0.51 + 0.49 * event['strength']) + 0.5), event
                    if data['version'] == 'R02':
                        assert 0 <= event['sweep_sample'] <= event['sweep_divisions'] <= 24, event
                    else:
                        assert event['source'] == 'solver_tooth', event
                        assert event['target_part'] in ('chassis', 'wheel', 'support'), event
                        assert len(event['point']) == 3 and all(map(math.isfinite, event['point'])), event
                    assert event['time'] - last_hit.get(kind, -10) >= combat[kind]['hit_cooldown'] - .002, event
                    last_hit[kind] = event['time']
                if (data['version'] in ('R05', 'R06') or identity) and event['major']:
                    assert event['strength'] >= .76 and event['closing_speed'] >= 3.8, event
            assert [hp[n] for n in names] == data['hp'], data
            if data['reason'] == 'knockout':
                assert min(data['hp']) == 0, data
            left, right = data['hp']
            tolerance = 0
            if identity:
                ratios = [left / maxima[0], right / maxima[1]]
                assert all(abs(a - b) < 1e-9 for a, b in zip(ratios, data['remaining_ratio'])), data
                if data['reason'] != 'knockout':
                    left, right = ratios
                    tolerance = 0.000001
            expected = 'DRAW' if abs(left - right) <= tolerance else names[0 if left > right else 1].upper()
            assert data['winner'] == expected, data
            summary = {k: data[k] for k in ('seed','winner','duration','hits','recoveries','max_arena_extent_ratio')}
            if solver or data['version'] == 'R02':
                clearance = data.get('min_detached_deck_clearance')
                if clearance is None:
                    assert data['lowest_root'] > .32, data
                else:
                    # Root height changes as missing supports let the chassis lean.
                    assert math.isfinite(clearance) and data['max_deep_deck_ticks'] <= 3, data
                assert data['peak_lift'] < .26 and data['peak_speed'] < 8, data
                for key in ('peak_lift', 'lowest_root', 'longest_close_run', 'wall_bumps', 'other_impacts'):
                    summary[key] = data[key]
            if solver:
                assert data['physics_hz'] == combat['physics_hz'], data
                if studio:
                    # The cut captures the deciding contact rather than a settled pose.
                    assert 0 <= data['end_weapon_contact_depth'] <= data['peak_weapon_contact_depth'], data
                else:
                    assert data['end_weapon_contact_depth'] < .025, data
                assert data['peak_weapon_contact_depth'] < .16, data
                assert data['longest_weapon_depth_over_25mm'] < .12, data
                for key in ('reason', 'physics_hz', 'peak_weapon_contact_depth',
                            'longest_weapon_depth_over_25mm', 'end_weapon_contact_depth', 'end_center_gap'):
                    summary[key] = data[key]
            if components:
                post_fight = episode['showcase_seconds'] if studio else (2.8 if identity else 3.8 - intro)
                assert abs(data['duration'] - intro - data['fight_duration'] - post_fight) < .04, data
                part_by_event = {
                    'armor_damaged': ('chassis', 'support'),
                    'wheel_damaged': ('wheel',),
                    'wheel_severe': ('wheel',),
                    'wheel_drive_failed': ('wheel',),
                    'wheel_detached': ('wheel',),
                    'weapon_disabled': ('support',),
                }
                seen_components = set()
                for item in data['component_events']:
                    assert item['kind'] in part_by_event, item
                    assert any(
                        hit['time'] == item['time'] and hit['attacker'] != item['robot']
                        and hit['target_part'] in part_by_event[item['kind']]
                        for hit in data['events']
                    ), item
                    if item['kind'] == 'weapon_disabled':
                        assert not any(hit['attacker'] == item['robot'] and hit['time'] > item['time']
                                       for hit in data['events']), data
                    if data['version'] == 'R06' or identity:
                        key = (item['robot'], item['kind'], item.get('wheel'))
                        assert key not in seen_components, item
                        seen_components.add(key)
                        if item['kind'].startswith('wheel_'):
                            assert item['wheel'] in range(4), item
                summary.update(maneuvers=data['maneuvers'], component_events=data['component_events'])
            if studio:
                for key in ('intro_duration', 'fight_duration', 'showcase_duration', 'hp', 'final_conditions'):
                    summary[key] = data[key]
            summaries.append(summary)
            print(f"PASS seed={seed} winner={data['winner']} duration={data['duration']:.2f}s hits={data['hits']}")
    output = project / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summaries, indent=2) + '\n')
    print(f'{len(summaries)} real Godot simulations passed. Visuals and recording require separate checks.')

if __name__ == '__main__':
    main()
