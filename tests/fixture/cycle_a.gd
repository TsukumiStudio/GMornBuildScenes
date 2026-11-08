extends RefCounted
## cycle_b.gd と互いに preload する。閉包は止まる。
const B := preload("cycle_b.gd")
