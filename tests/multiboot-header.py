import sys,struct
d=open(sys.argv[1],'rb').read(8192)
for off in range(0,8192-12,4):
    m,f,c=struct.unpack_from('<III',d,off)
    if m==0x1BADB002 and (m+f+c)&0xffffffff==0:
        v=struct.unpack_from('<4I',d,off+32) if f&4 else None
        print(f"header@0x{off:x} flags=0x{f:08x} video={v}"); break
else: print("no header")
