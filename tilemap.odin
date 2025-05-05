package main

import "core:encoding/csv"
import "core:encoding/xml"
import "core:fmt"
import "core:math/linalg"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

draw_tilemap :: proc(tilemap: [dynamic][dynamic]string, textures: ^map[string]rl.Texture2D) {
	for row, j in tilemap {
		for path, i in row {
			cartesian: rl.Vector2 = {f32(i), f32(j)} * TILE_WIDTH / 2
			position := linalg.mul(M_TO_ISO, cartesian)
			_cartesian := linalg.mul(M_TO_CART, position)


			texture, ok := textures[path]
			if ok {
				rl.DrawTextureV(texture, position, rl.WHITE)
			}
		}
	}
}
load_tilemap_layer :: proc(filename: string, layer_name: string) -> [dynamic][dynamic]string {
	doc, err := xml.load_from_file(filename)
	if err != xml.Error.None {
		fmt.eprintfln("Failed to load %q: %s", filename, err)
		return nil
	}

	if doc.element_count == 0 {
		fmt.eprintln("No root element found.")
		return nil
	}

	root := doc.elements[0]

	// TODO: Currently only handling a single tileset per tilemap

	source: string
	for i in root.value {
		element := doc.elements[i.(u32)]
		if element.ident != "tileset" {
			continue
		}

		for attrib in element.attribs {
			if attrib.key == "source" {
				source = attrib.val
				break
			}
		}
	}

	if source == "" {
		fmt.eprintln("ERROR: Could not find `tileset` element with attribute `source`")
		return nil
	}
	tileset := load_tileset(source)
	defer unload_tileset(tileset)

	layer_id: u32 = 0
	for i in root.value {
		e := doc.elements[i.(u32)]
		if e.ident != "layer" {
			continue
		}

		name: string
		for attrib in e.attribs {
			if attrib.key == "name" {
				name = attrib.val
				break
			}
		}

		if name == layer_name {
			layer_id = i.(u32)
			break
		}

	}

	if layer_id == 0 {
		fmt.eprintfln("ERROR: Could not find layer with name %q", layer_name)
		return nil
	}

	// NOTE: We assume, each layer has only a single child `data`
	// The data element has only one attribute: `encoding="csv"`
	e := doc.elements[layer_id]
	assert(len(e.value) == 1)
	j := e.value[0]
	e2 := doc.elements[j.(u32)]
	assert(e2.ident == "data")
	assert(len(e2.attribs) == 1)
	assert(e2.attribs[0].key == "encoding")
	assert(e2.attribs[0].val == "csv")

	csv_data := e2.value[0].(string)
	id_tilemap := parse_csv_tilemap(csv_data)
	defer delete(id_tilemap)

	tilemap: [dynamic][dynamic]string
	for id_row in id_tilemap {
		row: [dynamic]string
		for id in id_row {
			path, ok := tileset[id]
			if ok {
				append(&row, strings.clone(path))
			} else {
				append(&row, "")
			}
		}
		append(&tilemap, row)
	}
	return tilemap
}

unload_tilemap :: proc(tilemap: [dynamic][dynamic]string) {
	for row in tilemap {
		for s in row {
			delete(s)
		}
		delete(row)
	}
	delete(tilemap)
}

parse_csv_tilemap :: proc(csv_data: string) -> [dynamic][dynamic]int {
	r: csv.Reader
	r.trim_leading_space = true
	r.reuse_record = true
	r.reuse_record_buffer = true
	r.fields_per_record = -1
	defer csv.reader_destroy(&r)

	csv.reader_init_with_string(&r, csv_data)
	// defer delete(csv_data)

	tilemap: [dynamic][dynamic]int
	for r, i, err in csv.iterator_next(&r) {
		row: [dynamic]int
		if err != nil {
			fmt.eprintfln("ERROR: CSV error: %s", err)
			return nil
		}
		for f, j in r {
			if f == "" {continue}
			n, ok := strconv.parse_int(f)
			if !ok {
				fmt.eprintfln("ERROR: Could not parse texture id %q to int", f)
				return nil
			}
			// TODO: Handle -1 here!
			append(&row, n - 1)

		}
		append(&tilemap, row)
	}
	return tilemap
}

load_tileset :: proc(filename: string) -> map[int]string {
	tileset := make(map[int]string)

	doc, err := xml.load_from_file(filename)
	if err != xml.Error.None {
		fmt.eprintfln("Failed to load %q: %s", filename, err)
		return nil
	}

	if doc.element_count == 0 {
		fmt.eprintln("No root element found.")
		return nil
	}

	root := doc.elements[0]
	for i in root.value {
		element := doc.elements[i.(u32)]
		if element.ident == "grid" {
			continue
		}

		// Tile element

		id: int = -1
		for attrib in element.attribs {
			if attrib.key == "id" {
				n, ok := strconv.parse_int(attrib.val)
				if !ok {
					fmt.eprintln("ERROR: Could not parse texture id")
					return nil
				}
				id = n
				break
			}
		}
		if id == -1 {
			fmt.eprintln("ERROR: Tile element has no attribute `id`")
			return nil
		}

		// Image element

		assert(len(element.value) == 1)
		j := element.value[0]
		image_element := doc.elements[j.(u32)]

		source: string
		for attrib in image_element.attribs {
			if attrib.key == "source" {
				source = attrib.val
				break
			}
		}
		if source == "" {
			fmt.eprintln("ERROR: Image element has not attribute `source`")
			return nil
		}

		tileset[id] = source
	}

	return tileset
}

unload_tileset :: proc(tileset: map[int]string) {
	delete(tileset)
}
