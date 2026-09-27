#!/bin/sh
# build.sh — сборка C/C++/TeX во временном каталоге.
# Коды: 1 вызов, 2 файл, 3 Output:, 4 тип, 5 компилятор,
#       6 mktemp, 7 компиляция, 8 копирование, 128+N сигнал.

prog=$(basename -- "$0")

die() {
    code=$1
    shift
    printf '%s: ошибка: %s\n' "$prog" "$*" >&2
    exit "$code"
}

tmpdir=""

cleanup() {
    if [ -n "$tmpdir" ] && [ -d "$tmpdir" ]; then
        cd / || :
        rm -rf -- "$tmpdir"
    fi
    tmpdir=""
}

on_signal() {
    cleanup
    trap - EXIT
    exit $((128 + $1))
}

# Ловушки ставим до создания каталога
trap cleanup EXIT
trap 'on_signal 1'  HUP
trap 'on_signal 2'  INT
trap 'on_signal 3'  QUIT
trap 'on_signal 15' TERM

[ $# -eq 1 ] || die 1 "использование: $prog ИСХОДНЫЙ_ФАЙЛ"

src=$1
[ -f "$src" ] || die 2 "файл '$src' не найден"
[ -r "$src" ] || die 2 "файл '$src' недоступен для чтения"

srcdir=$(cd -- "$(dirname -- "$src")" && pwd -P) || die 2 "не удалось определить каталог '$src'"
srcname=$(basename -- "$src")
srcabs="$srcdir/$srcname"

case $srcname in
    *.c)                       kind=c;   compiler=${CC:-cc}        ;;
    *.cpp|*.cc|*.cxx|*.C)      kind=cxx; compiler=${CXX:-c++}      ;;
    *.tex)                     kind=tex; compiler=${TEX:-pdflatex} ;;
    *) die 4 "неизвестный тип файла '$srcname'" ;;
esac

command -v "$compiler" >/dev/null 2>&1 || die 5 "компилятор '$compiler' не найден"

# Поиск комментария Output:
out=$(grep -E '^[[:space:]]*(//|/\*|%)[[:space:]]*Output:' "$srcabs" \
      | head -n 1 \
      | tr -d '\r' \
      | sed -e 's/^.*Output:[[:space:]]*//' \
            -e 's/[[:space:]]*\*\/.*$//' \
            -e 's/[[:space:]].*$//')

[ -n "$out" ] || die 3 "в '$src' нет комментария вида 'Output: ИМЯ'"

case $out in
    */*)   die 3 "имя результата '$out' не должно содержать '/'" ;;
    .|..)  die 3 "недопустимое имя результата '$out'" ;;
esac

[ "$out" != "$srcname" ] || die 3 "имя результата совпадает с исходным файлом"

# Временный каталог
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/build.XXXXXX") || { tmpdir=""; die 6 "mktemp не смог создать каталог"; }
TMPDIR=$tmpdir
export TMPDIR
cd -- "$tmpdir" || die 6 "не удалось перейти в '$tmpdir'"

# Сборка
case $kind in
    c|cxx)
        "$compiler" -o "$tmpdir/$out" "$srcabs" || die 7 "ошибка компиляции '$src'"
        result="$tmpdir/$out"
        ;;
    tex)
        job=${out%.pdf}
        TEXINPUTS="$srcdir:${TEXINPUTS:-}"
        export TEXINPUTS
        for pass in 1 2; do
            "$compiler" -interaction=nonstopmode -halt-on-error \
                        -output-directory="$tmpdir" -jobname="$job" \
                        "$srcabs" >"$tmpdir/build-$pass.out" 2>&1 \
                || { cat "$tmpdir/build-$pass.out" >&2
                     die 7 "ошибка сборки '$src' (проход $pass)"; }
        done
        result="$tmpdir/$job.pdf"
        ;;
esac

[ -f "$result" ] || die 7 "компилятор завершился, но '$result' не создан"

# Результат рядом с исходником
cp -- "$result" "$srcdir/$out" || die 8 "не удалось записать '$srcdir/$out'"

printf '%s: готово: %s\n' "$prog" "$srcdir/$out"
exit 0
