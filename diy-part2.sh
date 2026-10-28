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
# 清理 Lean 遗留符号，写入 24.10 正确的 target 配置
sed -i '/^CONFIG_TARGET_ipq40xx/d' .config
sed -i '/^CONFIG_TARGET_DEVICE_ipq40xx/d' .config
sed -i '/^CONFIG_TARGET_BOARD=/d' .config
sed -i '/^CONFIG_TARGET_SUBTARGET=/d' .config
sed -i '/^CONFIG_TARGET_PROFILE=/d' .config
sed -i '/^CONFIG_LINUX_5_4=/d' .config
sed -i 's/^CONFIG_TARGET_MULTI_PROFILE=y/# CONFIG_TARGET_MULTI_PROFILE is not set/' .config
sed -i 's/^CONFIG_TARGET_PER_DEVICE_ROOTFS=y/# CONFIG_TARGET_PER_DEVICE_ROOTFS is not set/' .config
cat >> .config << 'EOF'
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_ipq40xx_generic_DEVICE_hiwifi_c526a=y
EOF
# 1. 放入 DTS 设备树文件
# 这会把之前准备好的DTS文件放到内核源码的正确位置
mkdir -p target/linux/ipq40xx/files-6.6/arch/arm/boot/dts/qcom/
cat > target/linux/ipq40xx/files-6.6/arch/arm/boot/dts/qcom/qcom-ipq4019-c526a.dts << 'C526A_DTS_EOF'
// ===== 把你的 DTS 内容整个粘贴到这里 =====
// 从 `// SPDX-License-Identifier: GPL-2.0-or-later OR MIT` 开始
// 一直到最后一个 `};`
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
#include "qcom-ipq4019.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
#include <dt-bindings/leds/common.h>
#include <dt-bindings/soc/qcom,tcsr.h>

/ {
	model = "HiWiFi C526A";
	compatible = "hiwifi,c526a";

	aliases {
		led-boot = &led_status;
		led-failsafe = &led_status;
		led-running = &led_status;
		led-upgrade = &led_status;
		label-mac-device = &swport5; /* 以 WAN 口 MAC 作为标签 MAC，参考 A42 */
	};

	chosen {
		bootargs-append = " root=/dev/ubiblock0_1"; /* NAND 设备通用，需根据实际 rootfs 卷名核对 */
	};

	keys {
		compatible = "gpio-keys";

		reset {
			label = "reset";
			gpios = <&tlmm 59 GPIO_ACTIVE_LOW>; /* 沿用旧 DTS 的 reset GPIO */
			linux,code = <KEY_RESTART>;
		};
	};

	leds {
		compatible = "gpio-leds";

		led_status: status {
			function = LED_FUNCTION_STATUS;
			color = <LED_COLOR_ID_BLUE>; /* 需实机核对颜色，占位 */
			gpios = <&tlmm 0 GPIO_ACTIVE_HIGH>;
		};
	};
};

/* ---- TCSR & 必要外设（沿用 ipq40xx 通用配置） ---- */
&prng { status = "okay"; };
&crypto { status = "okay"; };
&cryptobam { status = "okay"; };
&blsp_dma { status = "okay"; };

&tlmm {
	serial_pins: serial_pinmux {
		mux {
			pins = "gpio60", "gpio61";
			function = "blsp_uart0";
			bias-disable;
		};
	};
};

&blsp1_uart1 {
	pinctrl-0 = <&serial_pins>;
	pinctrl-names = "default";
	status = "okay";
};

/* ---- USB ---- */
&usb3 {
	status = "okay";
};

&usb2 {
	status = "okay";
};

&usb2_hs_phy {
	status = "okay";
};

/* ---- NAND：C526A 的 128MB NAND 在 &nand 节点上 ---- */
&nand {
	status = "okay";

	partitions {
		compatible = "fixed-partitions";
		#address-cells = <1>;
		#size-cells = <1>;

		partition@0 {
			label = "u-boot";
			reg = <0x0 0x100000>;
			read-only;
		};

		partition@100000 {
			label = "u-boot-env";
			reg = <0x100000 0x80000>;
		};

		partition@180000 {
			label = "bdinfo";
			reg = <0x180000 0x80000>;
			read-only;

			nvmem-layout {
				compatible = "fixed-layout";
				#address-cells = <1>;
				#size-cells = <1>;

				/* 参考旧提交：Vfac_mac 在 bdinfo 的 ASCII 文本区，偏移需实机确认。
				   如果 24.10 支持 mac-base ASCII 布局，可改用 mac-base 引用整个分区。 */
				macaddr_bdinfo: macaddr@18a {
					reg = <0x18a 0x6>;
				};
			};
		};

		partition@200000 {
			label = "firmware";
			reg = <0x200000 0x7e00000>; /* 126MB，需按实际 flash 布局核对 */
			compatible = "denx,fit"; /* 或 "openwrt,ubi"，取决于镜像格式 */
		};
	};
};

/* ---- 交换机：DSA 核心 ---- */
&mdio {
	status = "okay";
};

&gmac {
	status = "okay";
};

&switch {
	status = "okay";
};

/*
 * 端口映射假设（必须根据旧 DTS 的 switch0 配置核对）：
 * 旧 DTS 中 switch0 的 0u@eth0（CPU）、2:lan、3:lan、4:lan、以及 WAN 口。
 * 在 QCA8075 + DSA 中，通常 CPU 口为 0，LAN 为 1~3，WAN 为 4 或 5。
 * 下面按「WAN = swport5，LAN1~3 = swport2/3/4」占位，请对照 QCA8075 的 PHY 地址修正。
 */
&swport2 {
	status = "okay";
	label = "lan1";
	nvmem-cell-names = "mac-address";
	nvmem-cells = <&macaddr_bdinfo>;
};

&swport3 {
	status = "okay";
	label = "lan2";
	nvmem-cell-names = "mac-address";
	nvmem-cells = <&macaddr_bdinfo>;
};

&swport4 {
	status = "okay";
	label = "lan3";
	nvmem-cell-names = "mac-address";
	nvmem-cells = <&macaddr_bdinfo>;
};

&swport5 {
	status = "okay";
	label = "wan";
	nvmem-cell-names = "mac-address";
	nvmem-cells = <&macaddr_bdinfo>;
};

/* ---- Wi-Fi：QCA4019 双频（旧硬件中的 5G 两路） ---- */
&wifi0 {
	status = "okay";
	qcom,ath10k-calibration-variant = "HiWiFi-C526A";
	nvmem-cell-names = "pre-calibration";
	nvmem-cells = <&precal_art_1000>;
};

&wifi1 {
	status = "okay";
	qcom,ath10k-calibration-variant = "HiWiFi-C526A";
	nvmem-cell-names = "pre-calibration";
	nvmem-cells = <&precal_art_5000>;
};

/* ---- ART 分区（QCA4019 校准数据来自 SPI NOR 的 ART 分区）---- */
&blsp1_spi1 {
	status = "okay";

	flash@0 {
		compatible = "jedec,spi-nor";
		reg = <0>;
		spi-max-frequency = <24000000>;

		partitions {
			compatible = "fixed-partitions";
			#address-cells = <1>;
			#size-cells = <1>;

			partition@0 {
				label = "0:ART";
				reg = <0x0 0x10000>; /* 64KB ART，需核对 */

				nvmem-layout {
					compatible = "fixed-layout";
					#address-cells = <1>;
					#size-cells = <1>;

					precal_art_1000: precal@1000 {
						reg = <0x1000 0x2f20>;
					};

					precal_art_5000: precal@5000 {
						reg = <0x5000 0x2f20>;
					};
				};
			};
		};
	};
};
// ===== DTS 内容结束 =====
C526A_DTS_EOF

# 2. 用 Python 精确注入 02_network，避免 sed 生成坏分支
python3 - << 'PYEOF'
import re
path = 'target/linux/ipq40xx/base-files/etc/board.d/02_network'
with open(path) as f:
    content = f.read()

# 先删掉可能已经存在的错误注入
content = re.sub(r'\thiwifi,c526a\)\|\\\n', '', content)

# 在 zyxel,nbg6617) 块的 ;; 之后插入独立的 C526A 分支
marker = '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "wan"\n\t\t;;\n'
c526a = '\thiwifi,c526a)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n\t\t;;\n'

if 'hiwifi,c526a)' not in content:
    content = content.replace(marker, marker + c526a, 1)

with open(path, 'w') as f:
    f.write(content)
print("02_network: C526A injected")
PYEOF

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
# 5. 强制写入正确的 target 配置（必须在 make defconfig 之前）
sed -i '/^CONFIG_TARGET_ipq40xx/d' .config
sed -i '/^CONFIG_TARGET_DEVICE_ipq40xx/d' .config
sed -i '/^CONFIG_TARGET_BOARD=/d' .config
sed -i '/^CONFIG_TARGET_SUBTARGET=/d' .config
sed -i '/^CONFIG_TARGET_PROFILE=/d' .config
cat >> .config << 'TARGET_EOF'
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_ipq40xx_generic_DEVICE_hiwifi_c526a=y
TARGET_EOF

# 手动下载并放置 upx 二进制，解决 mihomo 编译依赖缺失
UPX_VER="4.2.4"
UPX_URL="https://github.com/upx/upx/releases/download/v${UPX_VER}/upx-${UPX_VER}-amd64_linux.tar.xz"
wget -q "$UPX_URL" -O /tmp/upx.tar.xz && \
tar -xJf /tmp/upx.tar.xz -C /tmp --strip-components=1 && \
mkdir -p staging_dir/host/bin && \
cp /tmp/upx staging_dir/host/bin/upx && \
chmod +x staging_dir/host/bin/upx

# ========== 秘制菜谱 结束 ==========
