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
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate

# Modify default theme
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# ========== HiWiFi C526A 注入脚本 ==========

# 1. 写入 DTS 设备树文件
mkdir -p target/linux/ipq40xx/files-6.6/arch/arm/boot/dts/qcom/
cat > target/linux/ipq40xx/files-6.6/arch/arm/boot/dts/qcom/qcom-ipq4019-c526a.dts << 'C526A_DTS_EOF'
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
		label-mac-device = &swport5;
	};

	chosen {
		bootargs-append = " root=/dev/ubiblock0_1";
	};

	keys {
		compatible = "gpio-keys";

		reset {
			label = "reset";
			gpios = <&tlmm 59 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_RESTART>;
		};
	};

	leds {
		compatible = "gpio-leds";

		led_status: status {
			function = LED_FUNCTION_STATUS;
			color = <LED_COLOR_ID_BLUE>;
			gpios = <&tlmm 0 GPIO_ACTIVE_HIGH>;
		};
	};
};

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

&usb3 {
	status = "okay";
};

&usb2 {
	status = "okay";
};

&usb2_hs_phy {
	status = "okay";
};

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

				macaddr_bdinfo: macaddr@18a {
					reg = <0x18a 0x6>;
				};
			};
		};

		partition@200000 {
			label = "firmware";
			reg = <0x200000 0x7e00000>;
			compatible = "denx,fit";
		};
	};
};

&mdio {
	status = "okay";
};

&gmac {
	status = "okay";
};

&switch {
	status = "okay";
};

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
				reg = <0x0 0x10000>;

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
C526A_DTS_EOF

# 2. 注入 02_network（Python，避免 sed 生成坏分支）
python3 - << 'PYEOF'
import re

path = 'target/linux/ipq40xx/base-files/etc/board.d/02_network'
with open(path) as f:
    content = f.read()

# 删掉可能已经存在的错误注入
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

# 3. 添加设备定义到 generic.mk（UbiFit 模板，适配 NAND）
cat >> target/linux/ipq40xx/image/generic.mk << 'C526A_MK_EOF'

define Device/hiwifi_c526a
	$(call Device/FitImageLzma)
	$(call Device/UbiFit)
	DEVICE_VENDOR := HiWiFi
	DEVICE_MODEL := C526A
	SOC := qcom-ipq4019
	DEVICE_DTS := qcom-ipq4019-c526a
	DEVICE_PACKAGES := ipq-wifi-hiwifi_c526a \
		kmod-usb3 kmod-usb-dwc3 \
		kmod-mt7615e kmod-mt7615-firmware
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	IMAGE_SIZE := 126464k
endef
TARGET_DEVICES += hiwifi_c526a
C526A_MK_EOF

# 4. 添加 ipq-wifi 板级数据条目
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
sed -i '/^CONFIG_LINUX_5_4=/d' .config
sed -i 's/^CONFIG_TARGET_MULTI_PROFILE=y/# CONFIG_TARGET_MULTI_PROFILE is not set/' .config
sed -i 's/^CONFIG_TARGET_PER_DEVICE_ROOTFS=y/# CONFIG_TARGET_PER_DEVICE_ROOTFS is not set/' .config
cat >> .config << 'TARGET_EOF'
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_ipq40xx_generic_DEVICE_hiwifi_c526a=y
TARGET_EOF

# 6. 手动下载并放置 upx 二进制，解决 mihomo 编译依赖缺失
UPX_VER="4.2.4"
UPX_URL="https://github.com/upx/upx/releases/download/v${UPX_VER}/upx-${UPX_VER}-amd64_linux.tar.xz"
wget -q "$UPX_URL" -O /tmp/upx.tar.xz && \
tar -xJf /tmp/upx.tar.xz -C /tmp --strip-components=1 && \
mkdir -p staging_dir/host/bin && \
cp /tmp/upx staging_dir/host/bin/upx && \
chmod +x staging_dir/host/bin/upx

# ========== 注入脚本结束 ==========
