import AppKit
let folder = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let outer = NSBezierPath(ovalIn: NSRect(x: 80, y: 80, width: 864, height: 864))
NSColor(srgbRed:0.08, green:0.11, blue:0.16, alpha:1).setFill(); outer.fill()
let inner = NSBezierPath(ovalIn: NSRect(x: 106, y: 106, width: 812, height: 812))
NSColor(srgbRed:0.98, green:0.96, blue:0.89, alpha:1).setFill(); inner.fill()
NSGraphicsContext.saveGraphicsState(); inner.addClip()
NSColor(srgbRed:0.91, green:0.19, blue:0.24, alpha:1).setFill(); NSBezierPath(rect:NSRect(x:100,y:512,width:824,height:410)).fill()
NSColor(srgbRed:0.08,green:0.11,blue:0.16,alpha:1).setFill(); NSBezierPath(rect:NSRect(x:90,y:477,width:850,height:70)).fill()
NSGraphicsContext.restoreGraphicsState()
for (radius, color) in [(142.0, NSColor(srgbRed:0.08,green:0.11,blue:0.16,alpha:1)),(108.0,NSColor.white),(60.0,NSColor(srgbRed:0.84,green:0.90,blue:0.93,alpha:1))] {
 color.setFill(); NSBezierPath(ovalIn:NSRect(x:512-radius,y:512-radius,width:radius*2,height:radius*2)).fill()
}
image.unlockFocus()
for size in [16,32,128,256,512] {
 for multiplier in [1,2] {
  let pixels = size*multiplier
  let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
  image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels)); NSGraphicsContext.restoreGraphicsState()
  let data = bitmap.representation(using:.png,properties:[:])!
  try data.write(to:URL(fileURLWithPath:folder+"/icon_\(size)x\(size)\(multiplier==2 ? "@2x" : "").png"))
 }
}

if CommandLine.arguments.count > 2 {
 var chunks = Data()
 let entries = [("icp4","icon_16x16.png"),("icp5","icon_32x32.png"),("icp6","icon_32x32@2x.png"),("ic07","icon_128x128.png"),("ic08","icon_256x256.png"),("ic09","icon_512x512.png"),("ic10","icon_512x512@2x.png"),("ic11","icon_16x16@2x.png"),("ic12","icon_32x32@2x.png"),("ic13","icon_128x128@2x.png"),("ic14","icon_256x256@2x.png")]
 for (type, filename) in entries {
  let png = try Data(contentsOf:URL(fileURLWithPath:folder+"/"+filename))
  chunks.append(Data(type.utf8)); var length = UInt32(png.count+8).bigEndian
  withUnsafeBytes(of:&length) { chunks.append(contentsOf:$0) }; chunks.append(png)
 }
 var result = Data("icns".utf8);var length = UInt32(chunks.count+8).bigEndian
 withUnsafeBytes(of:&length) { result.append(contentsOf:$0) };result.append(chunks)
 try result.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
}
