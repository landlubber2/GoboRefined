#!/bin/bash
# Lab only (0.8 A/B test): make the next build visibly different from the previous one.
# Run in the build VM BEFORE spin/build-iso.sh, as root:
#   wget -qO- http://10.0.2.2:8766/ab-test-variant.sh | bash
# Adds a new program (HelloAB 1.0, command hello-ab) and changes one file of an existing
# program (CoreUtils' Resources/Description). The version string comes from VERSION= of build-iso.
set -e
R=/Data/Build/rootfs
P=$R/Programs/HelloAB
rm -rf $P
mkdir -p $P/1.0/bin $P/1.0/Resources
cat > $P/1.0/bin/hello-ab <<'EOF'
#!/bin/sh
echo "hello from HelloAB 1.0 (new program in the 0.8 A/B update test image)"
EOF
chmod 755 $P/1.0/bin/hello-ab
echo "Lab test program for the GoboRefined 0.8 A/B update test." > $P/1.0/Resources/Description
ln -sfn 1.0 $P/Current
mount -t proc proc $R/proc
chroot $R SymlinkProgram HelloAB | tail -n 1
umount $R/proc
[ -L $R/System/Index/bin/hello-ab ]
d=$R/Programs/CoreUtils/Current/Resources/Description
grep -q 'A/B update test change' $d || echo "(GoboRefined 0.8 A/B update test change: this line is new in the second test image.)" >> $d
echo "test variant applied"
