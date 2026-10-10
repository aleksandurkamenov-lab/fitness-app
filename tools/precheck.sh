#!/usr/bin/env bash
# Бързи проверки преди качване (без swift). Излиза с код 1 при проблем.
cd "$(dirname "$0")/.." || exit 1
fail=0
bad() { echo "ПРОБЛЕМ: $1"; fail=1; }

# 1. Невалиден Section с footer
if grep -rn --include=*.swift -A8 -E 'Section\("' FitnessApp | grep -q 'footer:'; then
  echo "ВНИМАНИЕ: Section(\"...\") с footer: провери ръчно (трябва Section { } header: { } footer: { })"
fi

# 2. Версията във футъра = последния ред в CHANGELOG
foot=$(grep -oE 'Версия v[0-9]+' FitnessApp/Features/Workouts/WorkoutsView.swift | head -1 | grep -oE '[0-9]+')
last=$(grep -oE '^- v[0-9]+' CHANGELOG.md | tail -1 | grep -oE '[0-9]+')
[ "$foot" = "$last" ] || echo "ЗАБЕЛЕЖКА: футър v$foot, CHANGELOG v$last (ок само ако промяната не е в приложението)"

# 3. Всеки @Model е регистриран в modelContainer
for m in $(grep -rhoE '@Model[[:space:]]+(final )?class [A-Za-z]+' FitnessApp --include=*.swift | awk '{print $NF}'); do
  grep -q "$m" FitnessApp/App/FitnessApp.swift || bad "@Model $m не е в App/FitnessApp.swift"
done

# 4. Принудително разопаковане в сервизите
n=$(grep -rnE '[A-Za-z)\]]!\.|[A-Za-z)\]]![[:space:]),]' FitnessApp/Services --include=*.swift | grep -v '!=' | wc -l)
[ "$n" -gt 0 ] && echo "ЗАБЕЛЕЖКА: $n места с '!' в Services (виж с grep)"

# 5. Скоби се балансират във всеки файл (грубо)
for f in $(git diff --name-only HEAD~1 -- 'FitnessApp/*.swift' 2>/dev/null); do
  [ -f "$f" ] || continue
  o=$(tr -cd '{' < "$f" | wc -c); c=$(tr -cd '}' < "$f" | wc -c)
  [ "$o" = "$c" ] || bad "$f: { $o } $c"
  o=$(tr -cd '(' < "$f" | wc -c); c=$(tr -cd ')' < "$f" | wc -c)
  [ "$o" = "$c" ] || bad "$f: ( $o ) $c"
done

[ $fail = 0 ] && echo "precheck: ок" || exit 1
