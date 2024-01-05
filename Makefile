
initramfs:
	cd initramfs_dir && find . -print0 | cpio -ov --null --format=newc | gzip -9 > ../initramfs.img


run:
	qemu-system-x86_64 \
		-kernel bzImage \
		-initrd initramfs.img \
		-m 256M \
		-nographic \
		-append "earlyprintk=serial,ttyS0 console=ttyS0 nokaslr" \
		-S \
		-s
