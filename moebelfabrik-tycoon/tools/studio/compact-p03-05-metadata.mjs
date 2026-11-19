import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'

const source = JSON.parse(readFileSync(new URL('../../assets/p03-models/p03-05-import/checks.json', import.meta.url), 'utf8'))
const round = (value) => Number(value.toFixed(6))
const materials = []
const materialIds = new Map()
const assets = {}

for (const [name, asset] of Object.entries(source.assets)) {
  const meshes = asset.meshes.map((mesh) => {
    assert.equal(mesh.materials.length, 1, mesh.name)
    const material = mesh.materials[0]
    assert.ok(material.textures.length < 2, mesh.name)
    const spec = [...material.base_color_linear.slice(0, 3).map(round), material.textures[0]?.file ?? '']
    const key = JSON.stringify(spec)
    if (!materialIds.has(key)) {
      materials.push(spec)
      materialIds.set(key, materials.length)
    }
    const bounds = mesh.bounds_root_blender_m
    return [mesh.name, bounds.min.map(round), bounds.max.map(round), materialIds.get(key)]
  })
  assert.equal(new Set(meshes.map(([name]) => name)).size, asset.mesh_count, name)
  const bounds = asset.bounds_root_blender_m
  assets[name] = { bounds: [bounds.min.map(round), bounds.max.map(round)], meshes }
}

console.log(JSON.stringify({ task: 'P03-05', schema: 'normalize-v1', materials, assets }))
