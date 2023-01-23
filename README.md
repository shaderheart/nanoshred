# nanoshred
 
 nanoshred is an experimental game engine implemented (mostly) in Swift.
 
 ## Features
 - Compatible with iOS15.0+, macOS Catalyst 15.0+
 - Works with GLTF files using shredder extras for declaring entity components and scripts, through a custom GLTF importer
 - Custom ECS implementation using sparse maps, can handle up to 40000(+?) objects per core per frame
 - Exports component and script JSON maps automatically on build
 - Automatic packing of scene resources into the .app bundle on build
 - Automatic scene reloading on re-exports from shredder
 - Custom MIDI importer and manager for music-synced event support
 - Custom PBR renderer implemented with Metal2, with alpha-clipped and glass material support
 - Uses PhysX for physics through an ObjC++-Swift binding layer
 - Video-as-a-texture support using AVKit
 - Tap detectors and on-screen tappable objects using the renderer
 
 ## Screenshots
 Car Scene with an HDRI Background, Reflections and Glass:
![Screenshot 2023-01-23 at 23 02 38](https://user-images.githubusercontent.com/69399262/214138728-9f0b7871-19e6-4f39-94b5-d3ed11e27b2b.png)
![Screenshot 2023-01-23 at 23 02 59](https://user-images.githubusercontent.com/69399262/214138755-8da05bba-4bed-486c-a068-c53f1ee44d56.png)

Material rough/metallic, HDRI Background and Reflections:
![Screenshot 2023-01-23 at 22 45 31](https://user-images.githubusercontent.com/69399262/214137714-105202db-4597-4281-abc9-2d3b6d60b401.png)
