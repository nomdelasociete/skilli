ObjC.import('CoreGraphics');
const list = ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0));
const out = [];
for (let i = 0; i < list.count; i++) { const w = list.objectAtIndex(i); const layer = w.objectForKey('kCGWindowLayer').js; if (layer != 0) out.push(w.objectForKey('kCGWindowOwnerName').js + ' L' + layer); }
out.join('\n');
