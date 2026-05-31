#!/bin/bash
# 花生壳管理工具 — 封装花生壳云端 API、本地客户端 API 和 phddns CLI
set -euo pipefail

HSK_API="${HSK_API:-https://hsk-api.oray.com}"
LOCAL_API="${LOCAL_API:-http://127.0.0.1:16062}"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---- API Key 解析（三层 fallback：CLI flag > 环境变量 > 配置文件）----
HSK_CONF="${HSK_CONF:-$HOME/.hsk.conf}"

resolve_apikey() {
  [[ -n "${HSK_APIKEY:-}" ]] && return 0
  if [[ -f "$HSK_CONF" ]]; then
    source "$HSK_CONF"
    [[ -n "${HSK_APIKEY:-}" ]] && return 0
  fi
  return 1
}

# ---- 辅助函数 ----
check_deps() {
  if ! command -v curl &>/dev/null; then
    echo -e "${RED}[ERROR]${NC} curl 未安装" >&2
    exit 1
  fi
  if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}[WARN]${NC} jq 未安装，尝试使用 brew 安装..." >&2
    if command -v brew &>/dev/null; then
      brew install jq
    else
      echo -e "${RED}[ERROR]${NC} 请先安装 jq" >&2
      exit 1
    fi
  fi
}

check_apikey() {
  if ! resolve_apikey; then
    echo -e "${RED}[ERROR]${NC} 未找到 API Key，请通过以下任一方式提供：" >&2
    echo "  1) 命令行: hsk.sh --apikey <key> <命令>" >&2
    echo "  2) 环境变量: export HSK_APIKEY=\"your-api-key\"" >&2
    echo "  3) 配置文件: echo 'HSK_APIKEY=your-api-key' > $HSK_CONF && chmod 600 $HSK_CONF" >&2
    exit 1
  fi
}

auth_header() {
  echo "Authorization: apikey $HSK_APIKEY"
}

api_get() {
  local url="$1"
  curl -s -H "$(auth_header)" "$HSK_API$url"
}

api_post() {
  local url="$1"
  local data="$2"
  curl -s -H "$(auth_header)" -H "Content-Type: application/json" -X POST -d "$data" "$HSK_API$url"
}

api_put() {
  local url="$1"
  local data="$2"
  curl -s -H "$(auth_header)" -H "Content-Type: application/json" -X PUT -d "$data" "$HSK_API$url"
}

api_delete() {
  local url="$1"
  local data="${2:-}"
  if [[ -n "$data" ]]; then
    curl -s -H "$(auth_header)" -H "Content-Type: application/json" -X DELETE -d "$data" "$HSK_API$url"
  else
    curl -s -H "$(auth_header)" -X DELETE "$HSK_API$url"
  fi
}

local_get() {
  local url="$1"
  curl -s --connect-timeout 3 "$LOCAL_API$url" 2>/dev/null || true
}

# fwtype 数字 → 可读标签
fwtype_label() {
  case "${1:-}" in
    1) echo "TCP" ;;
    2) echo "HTTP" ;;
    3) echo "HTTPS" ;;
    4) echo "UDP" ;;
    *) echo "$1" ;;
  esac
}

# 检查 API 返回是否为错误（有些接口返回裸数组=成功）
check_response() {
  local resp="$1"
  # 裸数组是正常响应（如 mapping list）
  if echo "$resp" | jq -e 'type == "array"' &>/dev/null; then
    return 0
  fi
  local code
  code=$(echo "$resp" | jq -r '.code // .status // empty' 2>/dev/null)
  if [[ -n "$code" && "$code" != "0" && "$code" != "200" ]]; then
    local msg
    msg=$(echo "$resp" | jq -r '.msg // .message // "未知错误"' 2>/dev/null)
    echo -e "${RED}[API 错误]${NC} code=$code, msg=$msg" >&2
    return 1
  fi
  return 0
}

# 表格辅助
table_header() {
  printf "${BOLD}%-20s %-35s %-6s %-8s %-22s %-8s %-12s${NC}\n" \
    "名称" "域名" "外网端口" "协议" "内网地址" "内网端口" "状态"
  printf "%-20s %-35s %-6s %-8s %-22s %-8s %-12s\n" \
    "--------------------" "-----------------------------------" "------" "--------" "----------------------" "--------" "------------"
}

# ---- 映射管理 ----
mapping_cmd() {
  check_apikey
  case "${2:-}" in
    list)   mapping_list ;;
    create) mapping_create "$@" ;;
    update) mapping_update "$@" ;;
    delete) mapping_delete "$@" ;;
    toggle) mapping_toggle "$@" ;;
    *)
      echo "用法: hsk.sh mapping <list|create|update|delete|toggle> [参数]"
      echo ""
      echo "  list                      列出所有映射"
      echo "  create --domain <d> --port <p> --fwtype <t> --inner-host <h> --inner-port <p>"
      echo "  update <domain> <port> <fwtype> '<json>'    更新映射（JSON 为要修改的字段）"
      echo "  delete <domain> <port> <fwtype>             删除映射"
      echo "  toggle <domain> <port> <fwtype> <on|off>    启用/禁用映射"
      ;;
  esac
}

mapping_list() {
  echo -e "${CYAN}正在获取映射列表...${NC}"
  local resp
  resp=$(api_get "/openapi/v2/mapping/list")
  check_response "$resp" || { echo "$resp" | jq .; return 1; }

  # 检查是否为空数组
  if [[ "$resp" == "[]" ]]; then
    echo "暂无映射"
    return
  fi

  local count
  count=$(echo "$resp" | jq -r 'length')
  echo -e "共 ${BOLD}$count${NC} 条映射："
  echo ""
  table_header

  echo "$resp" | jq -r '.[] | "\(.memo // "无")|\(.domain)|\(.port)|\(.fwtype)|\(.servicehost)|\(.serviceport)|\(.isforbid)"' \
    | while IFS='|' read -r memo domain port fwtype host sport isforbid; do
    local fwlabel
    fwlabel=$(fwtype_label "$fwtype")
    local color="$GREEN"
    local status="运行中"
    if [[ "$isforbid" == "true" ]]; then
      color="$RED"
      status="已禁用"
    fi
    printf "%-20s %-35s %-6s %-8s %-22s %-8s ${color}%-12s${NC}\n" \
      "$memo" "$domain" "$port" "$fwlabel" "$host" "$sport" "$status"
  done
}

mapping_create() {
  shift 2
  local domain="" port="" fwtype="" inner_host="" inner_port="" memo=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)     domain="$2"; shift 2 ;;
      --port)       port="$2"; shift 2 ;;
      --fwtype)     fwtype="$2"; shift 2 ;;
      --inner-host) inner_host="$2"; shift 2 ;;
      --inner-port) inner_port="$2"; shift 2 ;;
      --memo)       memo="$2"; shift 2 ;;
      *) echo -e "${RED}未知参数: $1${NC}"; return 1 ;;
    esac
  done

  if [[ -z "$domain" || -z "$port" || -z "$fwtype" || -z "$inner_host" || -z "$inner_port" ]]; then
    echo -e "${RED}[ERROR]${NC} 缺少必填参数" >&2
    echo "必填: --domain <域名> --port <端口> --fwtype <协议> --inner-host <内网IP> --inner-port <内网端口>"
    return 1
  fi

  local payload
  payload=$(jq -n \
    --arg domain "$domain" \
    --arg port "$port" \
    --arg fwtype "$fwtype" \
    --arg servicehost "$inner_host" \
    --arg serviceport "$inner_port" \
    --arg memo "${memo:-映射}" \
    '{
      domain: $domain,
      port: ($port | tonumber),
      fwtype: ($fwtype | tonumber),
      servicehost: $servicehost,
      serviceport: ($serviceport | tonumber),
      memo: $memo,
      type: 1,
      bandwidth: 1,
      logoid: 0,
      key: ""
    }')

  echo -e "${CYAN}正在创建映射...${NC}"
  local resp
  resp=$(api_post "/openapi/v2/mapping/create" "$payload")
  check_response "$resp" || { echo "$resp" | jq .; return 1; }
  echo -e "${GREEN}映射创建成功${NC}"
  echo "$resp" | jq .
}

mapping_update() {
  local domain="${3:-}" port="${4:-}" fwtype="${5:-}" update_json="${6:-}"

  if [[ -z "$domain" || -z "$port" || -z "$fwtype" || -z "$update_json" ]]; then
    echo "用法: hsk.sh mapping update <domain> <port> <fwtype> '<json>'"
    echo "示例: hsk.sh mapping update test.oray.vip 8080 2 '{\"servicehost\":\"192.168.1.100\",\"serviceport\":9090}'"
    return 1
  fi

  # 先取当前映射，确保 memo 和 fwtype 必填字段存在
  echo -e "${CYAN}正在查找映射...${NC}"
  local mapping
  mapping=$(api_get "/openapi/v2/mapping/list" | jq --arg d "$domain" --arg p "$port" --arg f "$fwtype" \
    '.[] | select(.domain == $d and (.port | tostring) == $p and (.fwtype | tostring) == $f)')

  if [[ -z "$mapping" || "$mapping" == "null" ]]; then
    echo -e "${RED}[ERROR]${NC} 未找到匹配的映射: domain=$domain port=$port fwtype=$fwtype"
    return 1
  fi

  # 以当前 mapping 为基础，合并用户提供的更新字段
  local payload
  payload=$(echo "$mapping" | jq --argjson updates "$update_json" '
    { memo, fwtype, servicehost, serviceport } + $updates
  ')

  echo -e "${CYAN}正在更新映射...${NC}"
  local resp
  resp=$(api_put "/openapi/v2/mappings/$domain/$port/$fwtype" "$payload")
  if [[ -z "$resp" ]]; then
    echo -e "${GREEN}映射更新成功${NC}"
  else
    check_response "$resp" || { echo "$resp" | jq .; return 1; }
    echo -e "${GREEN}映射更新成功${NC}"
    echo "$resp" | jq .
  fi
}

mapping_delete() {
  local domain="${3:-}" port="${4:-}" fwtype="${5:-}"

  if [[ -z "$domain" || -z "$port" || -z "$fwtype" ]]; then
    echo "用法: hsk.sh mapping delete <domain> <port> <fwtype>"
    return 1
  fi

  echo -e "${YELLOW}确认删除映射: domain=$domain port=$port fwtype=$fwtype${NC}"
  echo -n "输入 yes 确认: "
  read -r confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "已取消"
    return 0
  fi

  echo -e "${CYAN}正在删除映射...${NC}"
  local resp
  resp=$(api_delete "/openapi/v2/mappings/$domain/$port/$fwtype")
  if [[ -z "$resp" ]]; then
    echo -e "${GREEN}映射已删除${NC}"
  else
    check_response "$resp" || { echo "$resp" | jq .; return 1; }
    echo -e "${GREEN}映射已删除${NC}"
  fi
}

mapping_toggle() {
  local domain="${3:-}" port="${4:-}" fwtype="${5:-}" action="${6:-}"

  if [[ -z "$domain" || -z "$port" || -z "$fwtype" || -z "$action" ]]; then
    echo "用法: hsk.sh mapping toggle <domain> <port> <fwtype> <on|off>"
    return 1
  fi

  if [[ "$action" != "on" && "$action" != "off" ]]; then
    echo -e "${RED}[ERROR]${NC} 操作必须是 on 或 off，收到: $action"
    return 1
  fi

  local switch
  if [[ "$action" == "on" ]]; then switch="0"; else switch="1"; fi

  # 获取 userid
  local account
  account=$(api_get "/openapi/api/forward/service")
  local userid
  userid=$(echo "$account" | jq -r '.userid // empty')
  if [[ -z "$userid" || "$userid" == "null" ]]; then
    echo -e "${RED}[ERROR]${NC} 无法获取用户 ID"
    return 1
  fi

  # 查映射
  local resp
  resp=$(api_get "/openapi/v2/mapping/list")
  local mapping
  mapping=$(echo "$resp" | jq --arg d "$domain" --arg p "$port" --arg f "$fwtype" \
    '.[] | select(.domain == $d and (.port | tostring) == $p and (.fwtype | tostring) == $f)')

  if [[ -z "$mapping" || "$mapping" == "null" ]]; then
    echo -e "${RED}[ERROR]${NC} 未找到匹配的映射"
    return 1
  fi

  echo -e "${CYAN}正在${action}映射...${NC}"
  resp=$(api_post "/openapi/api/mapping/$userid/forbid/$switch" "$mapping")
  check_response "$resp" || { echo "$resp" | jq .; return 1; }
  echo -e "${GREEN}映射已${action}${NC}"
}

# ---- 域名管理 ----
domain_cmd() {
  check_apikey
  case "${2:-}" in
    list) domain_list ;;
    *) echo "用法: hsk.sh domain list" ;;
  esac
}

domain_list() {
  echo -e "${CYAN}正在获取域名列表...${NC}"
  local resp
  resp=$(api_get "/openapi/api/domain/list")
  check_response "$resp" || { echo "$resp" | jq .; return 1; }

  local items
  items=$(echo "$resp" | jq -r '.actived // empty')
  if [[ -z "$items" || "$items" == "null" ]]; then
    echo "暂无已激活的域名"
    return
  fi

  local count
  count=$(echo "$items" | jq -r 'length')
  echo -e "共 ${BOLD}$count${NC} 个域名："
  echo ""

  printf "${BOLD}%-40s %-12s %-10s${NC}\n" "域名" "域名 ID" "状态"
  printf "%-40s %-12s %-10s\n" "----------------------------------------" "------------" "----------"

  echo "$items" | jq -r '.[] | "\(.domainname)|\(.domainid)|\(.statuscode)"' \
    | while IFS='|' read -r name did scode; do
    local color="$GREEN"
    local slabel="已激活"
    if [[ "$scode" != "5017" ]]; then
      color="$YELLOW"
      slabel="$scode"
    fi
    printf "%-40s %-12s ${color}%-10s${NC}\n" "$name" "$did" "$slabel"
  done
}

# ---- 端口检测 ----
port_cmd() {
  check_apikey
  case "${2:-}" in
    check) port_check "${3:-}" ;;
    *) echo "用法: hsk.sh port check <端口号>" ;;
  esac
}

port_check() {
  local port="$1"
  if [[ -z "$port" ]]; then
    echo "用法: hsk.sh port check <端口号>"
    return 1
  fi
  echo -e "${CYAN}正在检测端口 $port 可用性...${NC}"
  api_get "/openapi/api/port/search?port=$port" | jq .
}

# ---- 账号信息 ----
account_cmd() {
  check_apikey
  case "${2:-}" in
    info) account_info ;;
    *) echo "用法: hsk.sh account info" ;;
  esac
}

account_info() {
  echo -e "${CYAN}正在获取账号信息...${NC}"
  local resp
  resp=$(api_get "/openapi/api/forward/service")
  check_response "$resp" || { echo "$resp" | jq .; return 1; }

  local userid totalflow usedflow bandwidth quantity usage expiredate
  userid=$(echo "$resp" | jq -r '.userid // "N/A"')
  totalflow=$(echo "$resp" | jq -r '.totalflow // 0')
  usedflow=$(echo "$resp" | jq -r '.usedflow // 0')
  bandwidth=$(echo "$resp" | jq -r '.bandwidth // "N/A"')
  quantity=$(echo "$resp" | jq -r '.quantity // "N/A"')
  usage=$(echo "$resp" | jq -r '.usage // "N/A"')
  expiredate=$(echo "$resp" | jq -r '.expiredate // "N/A"')

  # 流量换算
  local total_mb used_mb
  total_mb=$(echo "scale=1; $totalflow / 1048576" | bc 2>/dev/null || echo "N/A")
  used_mb=$(echo "scale=1; $usedflow / 1048576" | bc 2>/dev/null || echo "N/A")

  echo ""
  printf "${BOLD}账号信息${NC}\n"
  printf "%-15s %s\n" "用户 ID:" "$userid"
  printf "%-15s %s / %s" "映射数:" "$usage" "$quantity"
  echo ""
  printf "%-15s %s Mbps\n" "带宽:" "$bandwidth"
  printf "%-15s %s MB / %s MB\n" "流量:" "$used_mb" "$total_mb"
  printf "%-15s %s\n" "到期时间:" "$expiredate"
}

# ---- 设备信息（本地 API） ----
device_cmd() {
  case "${2:-}" in
    info) device_info ;;
    *) echo "用法: hsk.sh device info" ;;
  esac
}

device_info() {
  echo -e "${CYAN}正在获取本地设备信息...${NC}"

  local sn_resp mgr_resp
  sn_resp=$(local_get "/ora_service/getsn")
  mgr_resp=$(local_get "/ora_service/getmgrurl")

  if [[ -z "$sn_resp" ]]; then
    echo -e "${RED}[ERROR]${NC} 无法连接本地花生壳客户端 (http://127.0.0.1:16062)" >&2
    echo "请确认 phddns 客户端正在运行: hsk.sh client status" >&2
    return 1
  fi

  local sn password online public_ip mgr_url
  sn=$(echo "$sn_resp" | jq -r '.sn // .SN // "N/A"')
  password=$(echo "$sn_resp" | jq -r '.password // .pwd // "N/A"')
  online=$(echo "$sn_resp" | jq -r '.online // .status // "N/A"')
  public_ip=$(echo "$sn_resp" | jq -r '.pubip // .public_ip // "N/A"')
  mgr_url=$(echo "$mgr_resp" | jq -r '.url // .mgrurl // "N/A"' 2>/dev/null || echo "N/A")

  local color="$GREEN"
  if [[ "$online" == "0" || "$online" == "offline" || "$online" == "false" ]]; then
    color="$RED"
  fi

  echo ""
  printf "${BOLD}本地设备信息${NC}\n"
  printf "%-15s %s\n" "设备 SN:" "$sn"
  printf "%-15s %s\n" "密码:" "$password"
  printf "%-15s ${color}%s${NC}\n" "在线状态:" "$online"
  printf "%-15s %s\n" "公网 IP:" "$public_ip"
  printf "%-15s %s\n" "管理页面:" "$mgr_url"
}

# ---- 客户端管理 ----
client_cmd() {
  if ! command -v phddns &>/dev/null; then
    echo -e "${RED}[ERROR]${NC} phddns 命令未找到" >&2
    echo "请确认花生壳客户端已安装。下载地址: https://hsk.oray.com/download/" >&2
    return 1
  fi

  case "${2:-}" in
    start)    echo -e "${CYAN}启动花生壳客户端...${NC}"; sudo phddns start ;;
    stop)     echo -e "${CYAN}停止花生壳客户端...${NC}"; sudo phddns stop ;;
    restart)  echo -e "${CYAN}重启花生壳客户端...${NC}"; sudo phddns restart ;;
    status)   echo -e "${CYAN}客户端运行状态:${NC}"; phddns status ;;
    enable)   echo -e "${CYAN}设置开机自启...${NC}"; sudo phddns enable ;;
    disable)  echo -e "${CYAN}取消开机自启...${NC}"; sudo phddns disable ;;
    reset)    echo -e "${YELLOW}重置客户端...${NC}"; sudo phddns reset ;;
    version)  phddns version ;;
    *)        echo "用法: hsk.sh client <start|stop|restart|status|enable|disable|reset|version>" ;;
  esac
}

# ---- 连通性测试 ----
test_cmd() {
  local domain="${2:-}" port="${3:-}"

  if [[ -z "$domain" || -z "$port" ]]; then
    echo "用法: hsk.sh test <域名> <端口>"
    return 1
  fi

  echo -e "${BOLD}连通性测试: $domain:$port${NC}"
  echo ""

  # DNS 解析
  echo -n "DNS 解析... "
  local ip
  ip=$(dig +short "$domain" 2>/dev/null | head -1) || ip=$(host "$domain" 2>/dev/null | awk '/has address/ {print $NF}' | head -1) || true
  if [[ -n "$ip" ]]; then
    echo -e "${GREEN}OK${NC} ($ip)"
  else
    echo -e "${RED}FAIL${NC} — 无法解析域名"
    return 1
  fi

  # TCP 连通性
  echo -n "TCP 连接... "
  if command -v nc &>/dev/null; then
    if nc -z -w 5 "$domain" "$port" 2>/dev/null; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC} — 端口不可达"
      return 1
    fi
  else
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$domain:$port" 2>/dev/null || true)
    if [[ -n "$http_code" && "$http_code" != "000" ]]; then
      echo -e "${GREEN}OK${NC} (HTTP $http_code)"
    else
      echo -e "${RED}FAIL${NC} — 端口不可达"
      return 1
    fi
  fi

  # HTTP 响应
  echo -n "HTTP 检查... "
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$domain:$port" 2>/dev/null || true)
  if [[ -n "$http_code" && "$http_code" != "000" ]]; then
    if [[ "$http_code" -ge 200 && "$http_code" -lt 500 ]]; then
      echo -e "${GREEN}$http_code${NC}"
    else
      echo -e "${YELLOW}$http_code${NC}"
    fi
  else
    echo -e "${YELLOW}无 HTTP 响应（非 HTTP 服务）${NC}"
  fi

  echo ""
  echo -e "${GREEN}连通性测试完成${NC}"
}

# ---- 帮助 ----
usage() {
  echo "花生壳管理工具 — hsk.sh"
  echo ""
  echo -e "${BOLD}用法:${NC}"
  echo "  hsk.sh <命令> [参数]"
  echo ""
  echo -e "${BOLD}命令:${NC}"
  echo "  mapping list                             列出所有映射"
  echo "  mapping create --domain <d> --port <p> --fwtype <t> --inner-host <h> --inner-port <p>"
  echo "  mapping update <domain> <port> <fwtype> '<json>'"
  echo "  mapping delete <domain> <port> <fwtype>"
  echo "  mapping toggle <domain> <port> <fwtype> <on|off>"
  echo "  domain list                              列出可用域名"
  echo "  port check <port>                        检测端口可用性"
  echo "  account info                             查看账号信息"
  echo "  device info                              查看本地设备信息"
  echo "  client <start|stop|restart|status>       管理 phddns 客户端"
  echo "  test <domain> <port>                     测试映射连通性"
  echo ""
  echo -e "${BOLD}API Key 提供方式（优先级从高到低）:${NC}"
  echo "  1) 命令行:  --apikey <key>            一次性传入"
  echo "  2) 环境变量: HSK_APIKEY=<key>         会话级"
  echo "  3) 配置文件: $HSK_CONF                持久化存储（需 chmod 600）"
  echo ""
  echo -e "${BOLD}其它环境变量:${NC}"
  echo "  HSK_API       云端 API 地址（默认: https://hsk-api.oray.com）"
  echo "  LOCAL_API     本地 API 地址（默认: http://127.0.0.1:16062）"
  echo "  HSK_CONF      配置文件路径（默认: ~/.hsk.conf）"
}

# ---- 主入口 ----
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apikey) HSK_APIKEY="$2"; shift 2 ;;
      *) break ;;
    esac
  done

  check_deps

  case "${1:-}" in
    mapping)  mapping_cmd "$@" ;;
    domain)   domain_cmd "$@" ;;
    port)     port_cmd "$@" ;;
    account)  account_cmd "$@" ;;
    device)   device_cmd "$@" ;;
    client)   client_cmd "$@" ;;
    test)     test_cmd "$@" ;;
    help|--help|-h) usage ;;
    *)        usage ;;
  esac
}

main "$@"
