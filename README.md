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
 
 ## Screenshots
 Car Scene with an HDRI Background, Reflections and Glass:
![Screenshot 2023-01-23 at 10 58 15 copy](https://user-images.githubusercontent.com/69399262/214122056-406a2f5e-994d-427e-9acf-7e43f5b1bde6.png)
![Screenshot 2023-01-23 at 10 59 03 copy](https://user-images.githubusercontent.com/69399262/214122366-1bde8a55-d3e4-48e6-b9ef-ab264f69aa1e.png)

Material rough/metallic, HDRI Background and Reflections:
![Screenshot 2023-01-23 at 11 08 07](https://user-images.githubusercontent.com/69399262/214122531-eaaa7adc-db81-439e-80dd-724f1b874769.png)
