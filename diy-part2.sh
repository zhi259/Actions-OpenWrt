#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# ========== 这是给 HiWiFi C526A 的“秘制菜谱” ==========

# 1. 放入 DTS 设备树文件
# 这会把之前准备好的DTS文件放到内核源码的正确位置
mkdir -p target/linux/ipq40xx/files-6.6/arch/arm/boot/dts/qcom/
cat > target/linux/ipq40xx/files-6.6/arch/arm/boot/dts/qcom/qcom-ipq4019-c526a.dts << 'C526A_DTS_EOF'
// ===== 把你的 DTS 内容整个粘贴到这里 =====
// 从 `// SPDX-License-Identifier: GPL-2.0-or-later OR MIT` 开始
// 一直到最后一个 `};`
// ===== DTS 内容结束 =====
C526A_DTS_EOF

# 2. 把 C526A 添加到网络配置脚本 (02_network) 中
# 这会让系统在首次开机时知道如何初始化网口
sed -i '/8dev,habanero-dvk|\\/i\	hiwifi,c526a)|\\' target/linux/ipq40xx/base-files/etc/board.d/02_network
sed -i '/ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "wan"/i\		ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\;\\' target/linux/ipq40xx/base-files/etc/board.d/02_network

# 3. 把 C526A 的设备定义添加到镜像生成规则 (generic.mk) 中
# 这告诉编译系统如何为你的设备生成最终的固件文件
cat >> target/linux/ipq40xx/image/generic.mk << 'C526A_MK_EOF'

define Device/hiwifi_c526a
	$(Device/dsa-migration)
	DEVICE_VENDOR := HiWiFi
	DEVICE_MODEL := C526A
	DEVICE_DTS := qcom-ipq4019-c526a
	SOC := qcom-ipq4019
	DEVICE_PACKAGES := ipq-wifi-hiwifi_c526a \
		kmod-usb3 kmod-usb-dwc3 \
		kmod-mt7615e kmod-mt7615-firmware
	IMAGE_SIZE := 126464k
	IMAGES := sysupgrade.bin
	IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += hiwifi_c526a
C526A_MK_EOF

# 4. 添加 ipq-wifi 板级数据条目（数据文件本身需要你上传）
# 这是告诉编译系统，要去使用一个叫 board-hiwifi_c526a.qca4019 的文件
if ! grep -q "hiwifi_c526a" package/firmware/ipq-wifi/Makefile; then
	sed -i '/^ALLWIFIBOARDS:=/a\hiwifi_c526a' package/firmware/ipq-wifi/Makefile
	echo '$(eval $(call generate-ipq-wifi-package,hiwifi_c526a,HiWiFi C526A))' >> package/firmware/ipq-wifi/Makefile
fi

# ========== 秘制菜谱 结束 ==========
