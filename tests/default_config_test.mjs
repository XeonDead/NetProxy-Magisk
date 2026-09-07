import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const root = new URL('../', import.meta.url)
const readJSON = path => JSON.parse(readFileSync(new URL(path, root), 'utf8'))
const config = readJSON('src/module/config/singbox/config.json')
const upstream = readJSON('tests/fixtures/singbox-upstream.json')
const resources = readJSON('.github/resources.json').raw
const list = value => value === undefined ? [] : Array.isArray(value) ? value : [value]

test('默认配置仅保留部署与运行时生成所需的上游差异', () => {
  const expected = structuredClone(upstream)
  expected.log.output = '/data/adb/modules/netproxy/logs/sing-box.log'
  expected.experimental.cache_file.path = '/data/adb/modules/netproxy/config/singbox/cache.db'
  expected.experimental.clash_api.external_controller = '127.0.0.1:9999'
  expected.experimental.clash_api.external_ui = '/data/adb/modules/netproxy/webroot/zashboard'
  expected.services[0].listen = '127.0.0.1'
  expected.services[0].listen_port = 9090
  expected.services[0].dashboard.path = '/data/adb/modules/netproxy/webroot/sing-box-dashboard'
  expected.inbounds = expected.inbounds.filter(inbound => inbound.type !== 'ebpf')
  delete expected.outbounds
  delete expected.providers
  for (const rule of expected.route.rule_set) {
    rule.path = rule.path.replace('./source/rule_set/', './rules/remote/').replace('./source/', './rules/local/')
  }
  assert.deepEqual(config, expected)
})

test('eBPF 默认配置使用显式数据路径和新版数据平面', () => {
  const ebpf = readFileSync(new URL('src/module/config/ebpf/ebpf.conf', root), 'utf8')
  assert.match(ebpf, /^EBPF_LOCAL_ENABLED=1$/m)
  assert.match(ebpf, /^EBPF_LOCAL_DATA_PLANE="cgroup"$/m)
  assert.match(ebpf, /^EBPF_SHARED_ENABLED=0$/m)
  assert.match(ebpf, /^EBPF_SHARED_DATA_PLANE="packet_rewrite"$/m)
  assert.doesNotMatch(ebpf, /^EBPF_MODE=/m)
})
