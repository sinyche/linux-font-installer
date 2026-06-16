#!/bin/bash
# LFI 快速测试脚本 — 在本地验证功能
# 用法: bash test.sh

echo "LFI 功能测试"
echo "============"

# 1. 检查语法
echo -n "[1] 语法检查... "
bash -n lfi.sh 2>/dev/null && echo "OK" || echo "FAIL"
for m in modules/*.sh; do
    echo -n "    $m... "
    bash -n "$m" 2>/dev/null && echo "OK" || echo "FAIL"
done

# 2. 检查字体清单
echo -n "[2] 字体清单检查... "
for f in fonts/*/list.txt; do
    [ -s "$f" ] || echo "警告: $f 为空"
done
echo "OK"

# 3. 模拟启动（不实际安装）
echo -n "[3] 模拟启动... "
LFI_ROOT=/tmp/lfi-test bash -c 'source lfi.sh 2>&1 | head -5' || true
echo "（手动终止）"

echo ""
echo "测试完成"
