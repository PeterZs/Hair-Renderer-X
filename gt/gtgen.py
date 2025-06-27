# //////////////////////////////////////////
# GENERATES GROUND TRUTH IMAGE USING MITSUBA
# //////////////////////////////////////////

import mitsuba as mi
import os

mi.variants()
mi.set_variant('cuda_ad_rgb')

script_dir = os.path.dirname(os.path.abspath(__file__))
scene_file = os.path.join(script_dir, 'hair_scene.xml')
scene = mi.load_file(path=scene_file)

image = mi.render(scene,spp=128)

mi.util.write_bitmap("ground_truth.png", image)