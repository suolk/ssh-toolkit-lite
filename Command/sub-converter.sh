#!/bin/bash

set -e

SOURCE_FILE="/root/subscribe/sub-link.txt"
TARGET_DIR="/var/www/data/api/v1"
V2RAY_FILE="$TARGET_DIR/v2ray"
CLASH_FILE="$TARGET_DIR/clash"
DOMAIN="vps2.netcache24.site"

url_decode() {
    local value="${1//+/ }"
    printf '%b' "${value//%/\\x}"
}

yaml_quote() {
    local value
    value=$(printf '%s' "$1" | sed "s/'/''/g")
    printf "'%s'" "$value"
}

parse_name() {
    local line="$1"

    if [[ "$line" == *#* ]]; then
        url_decode "${line#*#}"
    else
        printf 'node'
    fi
}

query_get() {
    local query="$1"
    local key="$2"
    local pair pair_key pair_value

    IFS='&' read -ra pairs <<< "$query"
    for pair in "${pairs[@]}"; do
        pair_key="${pair%%=*}"
        pair_value="${pair#*=}"

        if [[ "$pair_key" == "$key" ]]; then
            url_decode "$pair_value"
            return 0
        fi
    done

    return 1
}

base64_url_decode() {
    local value="$1"
    local padding=$(( ${#value} % 4 ))

    value="${value//-/+}"
    value="${value//_//}"

    if (( padding > 0 )); then
        value+=$(printf '%*s' $((4 - padding)) '' | tr ' ' '=')
    fi

    printf '%s' "$value" | base64 -d
}

write_vless_proxy() {
    local line="$1"
    local rest main query uuid host_port server port name security network flow pbk sid sni fp tls

    rest="${line#vless://}"
    main="${rest%%\?*}"
    query=""

    if [[ "$rest" == *\?* ]]; then
        query="${rest#*\?}"
        query="${query%%#*}"
    fi

    uuid="${main%@*}"
    host_port="${main#*@}"
    host_port="${host_port%%/*}"
    server="${host_port%:*}"
    server="${server#[}"
    server="${server%]}"
    port="${host_port##*:}"
    name=$(parse_name "$line")

    security=$(query_get "$query" security || true)
    network=$(query_get "$query" type || true)
    flow=$(query_get "$query" flow || true)
    pbk=$(query_get "$query" pbk || true)
    sid=$(query_get "$query" sid || true)
    sni=$(query_get "$query" sni || true)
    fp=$(query_get "$query" fp || true)

    if [[ -z "$network" ]]; then
        network="tcp"
    fi

    tls="false"
    if [[ "$security" == "tls" || "$security" == "reality" ]]; then
        tls="true"
    fi

    {
        printf '  - name: %s\n' "$(yaml_quote "$name")"
        printf '    type: vless\n'
        printf '    server: %s\n' "$(yaml_quote "$server")"
        printf '    port: %s\n' "$port"
        printf '    uuid: %s\n' "$(yaml_quote "$uuid")"
        printf '    tls: %s\n' "$tls"
        printf '    udp: true\n'
        printf '    network: %s\n' "$(yaml_quote "$network")"

        if [[ -n "$flow" ]]; then
            printf '    flow: %s\n' "$(yaml_quote "$flow")"
        fi

        if [[ "$security" == "reality" ]]; then
            printf '    reality-opts:\n'
            printf '      public-key: %s\n' "$(yaml_quote "$pbk")"
            printf '      short-id: %s\n' "$(yaml_quote "$sid")"
        fi

        if [[ -n "$sni" ]]; then
            printf '    servername: %s\n' "$(yaml_quote "$sni")"
        fi

        if [[ -n "$fp" ]]; then
            printf '    client-fingerprint: %s\n' "$(yaml_quote "$fp")"
        fi
    } >> "$CLASH_FILE"
}

write_ss_proxy() {
    local line="$1"
    local main method_pass server_part decoded method password host_port host port name

    main="${line#ss://}"
    main="${main%%#*}"

    if [[ "$main" != *@* ]]; then
        return 1
    fi

    method_pass="${main%@*}"
    server_part="${main#*@}"
    decoded=$(base64_url_decode "$method_pass")
    method="${decoded%%:*}"
    password="${decoded#*:}"
    host_port="${server_part%%\?*}"
    host="${host_port%:*}"
    host="${host#[}"
    host="${host%]}"
    port="${host_port##*:}"
    name=$(parse_name "$line")

    {
        printf '  - name: %s\n' "$(yaml_quote "$name")"
        printf '    type: ss\n'
        printf '    server: %s\n' "$(yaml_quote "$host")"
        printf '    port: %s\n' "$port"
        printf '    cipher: %s\n' "$(yaml_quote "$method")"
        printf '    password: %s\n' "$(yaml_quote "$password")"
        printf '    udp: true\n'
    } >> "$CLASH_FILE"
}

write_hysteria2_proxy() {
    local line="$1"
    local rest main query userinfo host_port password server port name sni insecure skip_cert_verify

    rest="${line#hysteria2://}"
    main="${rest%%\?*}"
    query=""

    if [[ "$rest" == *\?* ]]; then
        query="${rest#*\?}"
        query="${query%%#*}"
    fi

    userinfo="${main%@*}"
    host_port="${main#*@}"
    host_port="${host_port%%/*}"
    password=$(url_decode "$userinfo")
    server="${host_port%:*}"
    server="${server#[}"
    server="${server%]}"
    port="${host_port##*:}"
    name=$(parse_name "$line")
    sni=$(query_get "$query" sni || true)
    insecure=$(query_get "$query" insecure || true)

    skip_cert_verify="false"
    if [[ "$insecure" == "1" ]]; then
        skip_cert_verify="true"
    fi

    {
        printf '  - name: %s\n' "$(yaml_quote "$name")"
        printf '    type: hysteria2\n'
        printf '    server: %s\n' "$(yaml_quote "$server")"
        printf '    port: %s\n' "$port"
        printf '    password: %s\n' "$(yaml_quote "$password")"
        printf '    sni: %s\n' "$(yaml_quote "$sni")"
        printf '    skip-cert-verify: %s\n' "$skip_cert_verify"
    } >> "$CLASH_FILE"
}

echo "准备目录..."
sudo mkdir -p "$TARGET_DIR"
sudo chown -R www-data:www-data /var/www/data

echo "生成 V2Ray Base64..."
base64 -w 0 "$SOURCE_FILE" > "$V2RAY_FILE"

echo "生成 Clash YAML..."

{
    printf 'port: 7890\n'
    printf 'socks-port: 7891\n'
    printf 'allow-lan: false\n'
    printf 'mode: rule\n'
    printf 'proxies:\n'
} > "$CLASH_FILE"

node_count=0
proxy_names=()

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue

    case "$line" in
        vless://*)
            write_vless_proxy "$line"
            proxy_names+=("$(parse_name "$line")")
            node_count=$((node_count + 1))
            ;;
        ss://*)
            if write_ss_proxy "$line"; then
                proxy_names+=("$(parse_name "$line")")
                node_count=$((node_count + 1))
            fi
            ;;
        hysteria2://*)
            write_hysteria2_proxy "$line"
            proxy_names+=("$(parse_name "$line")")
            node_count=$((node_count + 1))
            ;;
    esac
done < "$SOURCE_FILE"

{
    printf 'proxy-groups:\n'
    printf '  - name: Proxy\n'
    printf '    type: select\n'
    printf '    proxies:\n'

    for name in "${proxy_names[@]}"; do
        printf '      - %s\n' "$(yaml_quote "$name")"
    done

    printf 'rules:\n'
    printf '  - MATCH,Proxy\n'
} >> "$CLASH_FILE"

echo "Done:"
echo "output $CLASH_FILE"
echo "nodes number: $node_count"

echo "设置权限..."
sudo chmod 644 "$V2RAY_FILE"
sudo chmod 644 "$CLASH_FILE"

echo
echo "完成："
echo "V2Ray:"
echo "https://$DOMAIN/api/v1/v2ray"

echo
echo "Clash:"
echo "https://$DOMAIN/api/v1/clash"
