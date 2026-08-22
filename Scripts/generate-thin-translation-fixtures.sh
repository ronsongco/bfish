#!/bin/zsh

set -euo pipefail

output_directory="${1:-/tmp/bfish-thin-translation-v1}"
mkdir -p "$output_directory"

say -v Kyoko -o "$output_directory/ja.aiff" '今日は午後3時に東京駅で会いましょう。'
say -v Yuna -o "$output_directory/ko.aiff" '오늘 오후 3시에 서울역에서 만나요.'
say -v Tingting -o "$output_directory/zh.aiff" '我们今天下午三点在北京站见面吧。'
say -v Luciana -o "$output_directory/pt-BR.aiff" 'Vamos nos encontrar na Estação da Luz hoje às três da tarde.'

echo "Generated four project-authored fixtures in $output_directory"
