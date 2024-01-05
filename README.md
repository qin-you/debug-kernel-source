
# Prerequisite:

busybox   1.36
linux     5.15


# QEMU+GDB 搭建内核调试环境

## 1.下载编译内核
make menuconfig 需要勾选 (一般都有):
```c
Kernel hacking --->  
	  Compile-time checks and compiler options --->  
		    [*] Compile the kernel with debug info
```

## 2.下载编译busybox
(新版好编译，旧版编x86遇到不好处理的错误）、
编译busybox：make menuconfig 需勾选：
```c
Settings --->
	Build static binary (no shared libs)
```

make -j8  编译
之后看一下  file busybox 
检查得到的可执行文件是否是x86_64的，如果是则可以测试（arm架构应无法在x86测试，可执行文件而指令集不同）
```sh
./busybox ls    # 测试busybox里的ls程序
./busybox pwd
```
没问题再往下

make install
把命令都安装到 `_install` 目录下


## 3.制作initamfs

3.1 拷贝bzImage、busybox文件；新增init程序文件
```c
root@ubuntu:~/linux-demo# tree
.
├── bzImage
└── initramfs
    ├── bin
    │   └── busybox
    └── init
```

init的内容是：
```sh
#!/bin/busybox sh  
/bin/busybox echo "Hello "  
/bin/busybox sh
```
init最后一定要进入sh，否则执行完echo就会关闭，init作为1号进程是不能关闭的否则kernel panic。

3.2 **创建initramfs.img文件** （linux-demo/Makefile 实现，方便复用）
```c makefile
initramfs:
	cd initramfs_dir && find . -print0 | cpio -ov --null --format=newc | gzip -9 > ../initramfs.img
```
方法就是先cpio归档，再gzip压缩得到。

make initramfs 可以看到生成的initramfs.img. 
注：这里为了makefile起作用，把前面的initramfs目录名改成了initramfs_dir

initramfs_dir就是qemu虚拟机启动后的根目录，在宿主机这里做的更新可以同步到虚拟机内。

补充：initramfs已经基本替代initrd了。initramfs是由内核调用，帮助挂载rootfs、加载模块的。 
到initramfs对应的目录 （参考 [[Linux内核学习笔记#解压已有的initramfs.img以查看init程序]]），grep modprobe可以发现加载了很多模块，比如`modprobe i2c-zhaoxin` ，这里正是因为是内核调用的initramfs的init，才能找到i2c-zhaoxin.ko的位置。


## 4.安装qemu  gdb
安装qemu：
```sh
apt-get install qemu qemu-kvm libvirt-bin bridge-utils virt-manager

# 或者
install qemu qemu-utils qemu-kvm virt-manager libvirt-daemon-system libvirt-clients bridge-utils
```
qemu：可只要这一个，提供最基本的虚拟机功能，无网络管理、图形界面、加速
qemu-kvm: 需要机器支持kvm，安装以加速
libvirt-bin: 管理工具
bridge-utils：网络管理
virt-manager：图形界面

gdb
`apt install gdb`


## 5.qemu启动虚拟机测试 

linux-demo/Makefile 实现，方便复用

```c makefile
initramfs:
	cd initramfs_dir && find . -print0 | cpio -ov --null --format=newc | gzip -9 > ../initramfs.img

run:
	qemu-system-x86_64 \
		-kernel bzImage \
		-initrd initramfs.img \
		-m 1G \
		-nographic \
		-append "earlyprintk=serial,ttyS0 console=ttyS0" /* args for kernel */         
```

make run可以看到虚拟机启动了，最后会执行init程序作为第一个进程。我们可以在qemu虚拟机内执行busybox相关命令：
```sh
~ # busybox ls
bin   dev   init  root

~ # busybox tree
.
├── bin
│   └── busybox
├── dev
│   └── console
├── init
└── root

3 directories, 3 files
```
启动过程出现`sh: can't access tty; job control turned off`不影响。

退出qemu虚拟机快捷键： ctrl-a  x

改init后需要先make initramfs生成新的initrd再make run。

至此我们已经通过qemu启动了 由**自己编译的内核和根文件系统**组成的x86虚拟机。\

挂载proc目录：
busybox ps aux 无法在qemu虚拟机运行，因为少/proc目录，因此我们mount一下，在init程序中增加：
```sh
busybox mkdir -p /proc && busybox mount -t proc none /proc
```
-t指定type为proc类型，none表示没有对应的硬件设备。 busybox 或者 /bin/busybox都行，内核自动到/bin找

之后在qemu虚拟机执行ps就可以了，且可以看到/proc下有很多文件，是个常规的proc目录。

这里需要理解一下根文件系统和操作系统的关系，根文件系统提供【交互接口、重要文件、目录】，内部的逻辑是由os（如vfs）提供的，我们把/proc挂载为proc类型后，os自动会把相关数据输入到/proc目录。


## 6.使用GDB+QEMU调试内核
6.1 设置qemu虚拟机启动参数：
```c makefile
run:
	qemu-system-x86_64 \
		-kernel bzImage \
		-initrd initramfs.img \
		-m 256M \
		-nographic \
		-append "earlyprintk=serial,ttyS0 console=ttyS0 nokaslr" /* cmdline*/            -S \
		-s \
```
3个改动：
-S 表示开始时阻塞cpu执行
-s 开启gdb服务器，端口为1234. 若人为指定端口可以换成：`-gdb tcp::9876`
nokaslr 禁用内核地址空间随机布局  放在cmdline里。

6.2  GDB调试
进入内核源码树根目录，执行.
`gdb vmlinux`
(在可执行文件所在目录创建.gdbinit可以把前几句如设置端口、断点的命令放进去，gdb开始后自动进行， 需要根据warning修改一个文件)


进入gdb命令行后，连接到指定的gdb调试端口:
`target remote :1234`

之后就和一般调试一样的。 
`b start_kernel` 可以先跳到入口函数，查看地址和System.map中一致的。




## 7.使用VScode+QEMU调试内核

7.1 
vscode打开内核源码树根目录，我们将调试本目录下的vmlinux，服务端的vmlinux也是从这里拷过去的，两文件相同。

7.2
添加.vscode/launch.json脚本（手动 或打开一个c文件后点调试按钮可以自动生成该文件），然后编辑如下：
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "qemu-kernel-gdb",    // arbitrary
            "type":"cppdbg",
            "request": "launch",
            "miDebuggerServerAddress": "127.0.0.1:1234",  // -s
            "program": "${workspaceRoot}/vmlinux",  // program been debuged
            "args": [],                          // args for gdb, we dont need
            "stopAtEntry": false,
            "cwd": "${workspaceFolder}",     //current work directory
            "environment": [],
            "externalConsole": false,
            "logging": {
                "engineLogging": false
            },
            "MIMode": "gdb"
        }
    ]
}
```

这样vscode启动调试后将调试"${workspaceRoot}/vmlinux"，并且运行状态信息从服务端"127.0.0.1:1234"获取。

7.3
以上完成所需配置，现在在服务端，也就是linux-demo目录启动gdb调试，即make run，使用“-S -s”参数。
vscode中也启动调试即可

7.4 （本地vscode 可选）
本实验在一台vmware ubuntu虚拟机上完成，该虚拟机运行code极缓慢。 因此
使用windows宿主机启动vscode，通过remote-ssh连接到ubuntu虚拟机。 然后把win的vscode当作ubuntu上的vscode操作即可。 
gdb的tcp server ip可改可不改，可以改成172.16.25.128即ubuntu的ip。




