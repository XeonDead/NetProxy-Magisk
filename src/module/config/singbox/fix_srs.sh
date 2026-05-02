#!/system/bin/sh
# Скрипт для скачивания удалённых наборов правил из 06_route.json
JSON="confdir/06_route.json"

# 1. Обрезаем файл до содержимого rule_set (открывающая '[' и её закрывающая ']' на отдельной строке)
# 2. awk разбивает блоки по закрывающей фигурной скобке '}' (каждый объект набора)
# 3. если в объекте нашлись url и path – выводим их через пробел
# 4. читаем построчно и выполняем curl
sed -n '/"rule_set": \[/,/^[[:space:]]*\]/p' "$JSON" \
| awk 'BEGIN{RS="}"; FS=","}
{
    url=""; path=""
    for(i=1;i<=NF;i++){
        if($i ~ /"url"/){
            gsub(/.*"url"[[:space:]]*:[[:space:]]*"/, "", $i)
            gsub(/".*/, "", $i)
            url=$i
        }
        if($i ~ /"path"/){
            gsub(/.*"path"[[:space:]]*:[[:space:]]*"/, "", $i)
            gsub(/".*/, "", $i)
            path=$i
        }
    }
    if(url != "" && path != ""){
        print url, path
    }
}' \
| while read -r dl_url dl_path; do
    echo ">>> Скачиваю: $dl_url -> $dl_path"
    # -L следовать редиректам, -o выходной файл
    curl -L -o "$dl_path" "$dl_url"
done