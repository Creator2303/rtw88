SHELL := /bin/sh
KVER ?= $(if $(KERNELRELEASE),$(KERNELRELEASE),$(shell uname -r))
KSRC ?= $(if $(KERNEL_SRC),$(KERNEL_SRC),/lib/modules/$(KVER)/build)
FIRMWAREDIR := /lib/firmware/rtw88
#MODLIST := rtw_8723cs rtw_8723de rtw_8723ds rtw_8723du \
#	   rtw_8812au rtw_8814au rtw_8821au rtw_8821ce rtw_8821cs rtw_8821cu \
#	   rtw_8822be rtw_8822bs rtw_8822bu rtw_8822ce rtw_8822cs rtw_8822cu \
#	   rtw_8703b rtw_8723d rtw_8821a rtw_8812a rtw_8814a rtw_8821c rtw_8822b rtw_8822c \
#	   rtw_8723x rtw_88xxa rtw_pci rtw_sdio rtw_usb rtw_core

MODLIST := rtw_8814au rtw_8814a \
           rtw_usb rtw_core


# Handle the move of the entire rtw88 tree
ifneq ("","$(wildcard /lib/modules/$(KVER)/kernel/drivers/net/wireless/realtek)")
MODDESTDIR := /lib/modules/$(KVER)/kernel/drivers/net/wireless/realtek/rtw88
else
MODDESTDIR := /lib/modules/$(KVER)/kernel/drivers/net/wireless/rtw88
endif

ifneq ("$(INSTALL_MOD_PATH)", "")
DEPMOD_ARGS = -b $(INSTALL_MOD_PATH)
else
DEPMOD_ARGS =
endif

#Handle the compression option for modules in 3.18+
ifneq ("","$(wildcard $(MODDESTDIR)/*.ko.gz)")
COMPRESS_GZIP := y
endif
ifneq ("","$(wildcard $(MODDESTDIR)/*.ko.xz)")
COMPRESS_XZ := y
endif
ifneq ("","$(wildcard $(MODDESTDIR)/*.ko.zst)")
COMPRESS_ZSTD := y
endif

ifeq ("","$(wildcard MOK.der)")
NO_SKIP_SIGN := y
endif

EXTRA_CFLAGS += -O2 -std=gnu11 -Wno-declaration-after-statement
ifeq ($(CONFIG_PCI), y)
EXTRA_CFLAGS += -DCONFIG_RTW88_8822BE=1
EXTRA_CFLAGS += -DCONFIG_RTW88_8821CE=1
EXTRA_CFLAGS += -DCONFIG_RTW88_8822CE=1
EXTRA_CFLAGS += -DCONFIG_RTW88_8723DE=1
endif
EXTRA_CFLAGS += -DCONFIG_RTW88_DEBUG=1
EXTRA_CFLAGS += -DCONFIG_RTW88_DEBUGFS=1
#EXTRA_CFLAGS += -DCONFIG_RTW88_REGD_USER_REG_HINTS

obj-m		+= rtw_core.o
rtw_core-objs	+= main.o \
		   mac80211.o \
		   util.o \
		   debug.o \
		   tx.o \
		   rx.o \
		   mac.o \
		   phy.o \
		   coex.o \
		   efuse.o \
		   fw.o \
		   ps.o \
		   sec.o \
		   bf.o \
		   regd.o \
		   sar.o

ifeq ($(CONFIG_PM), y)
rtw_core-objs	+= wow.o
endif


obj-m		+= rtw_8814a.o
rtw_8814a-objs	:= rtw8814a.o rtw8814a_table.o

obj-m		+= rtw_8814au.o
rtw_8814au-objs	:= rtw8814au.o


obj-m		+= rtw_usb.o
rtw_usb-objs	:= usb.o

ccflags-y += -D__CHECK_ENDIAN__

all: 
	$(MAKE) -j`nproc` -C $(KSRC) M=$$PWD modules
	
install: all
	@install -D -m 644 -t $(MODDESTDIR) *.ko
	@install -D -m 644 -t $(FIRMWAREDIR) firmware/*.bin
	@install -D -m 644 -t /etc/modprobe.d blacklist-rtw88.conf

ifeq ($(COMPRESS_GZIP), y)
	@gzip -f $(MODDESTDIR)/*.ko
endif
ifeq ($(COMPRESS_XZ), y)
	@xz -f -C crc32 $(MODDESTDIR)/*.ko
endif
ifeq ($(COMPRESS_ZSTD), y)
	@zstd -f -q --rm $(MODDESTDIR)/*.ko
endif

	@depmod $(DEPMOD_ARGS) -a $(KVER)
	@echo "The rtw88 drivers and firmware files were installed successfully."

uninstall:
	@for mod in $(MODLIST); do \
		rmmod -s $$mod || true; \
	done
	@rm -vf $(MODDESTDIR)/rtw_*.ko*
	@rm -vf /etc/modprobe.d/blacklist-rtw88.conf
	@depmod $(DEPMOD_ARGS)
	@echo "The rtw88 drivers were removed successfully."

clean:
	$(MAKE) -C $(KSRC) M=$$PWD clean
	@rm -f MOK.*

sign:
ifeq ($(NO_SKIP_SIGN), y)
	@openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER -out MOK.der -nodes -days 36500 -subj "/CN=Custom MOK/"
	@mokutil --import MOK.der
else
	echo "Skipping key creation"
endif
	@for mod in $(wildcard *.ko); do \
		$(KSRC)/scripts/sign-file sha256 MOK.priv MOK.der $$mod; \
	done

sign-install: all sign install

