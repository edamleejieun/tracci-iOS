# Core/Network

Stage G 起，网络层实现迁至本地 Swift Package：

- `Packages/TracciNetworking`

本目录不再编译源文件；App Target 通过 package product `TracciNetworking` 依赖。
历史路径保留此说明，避免误把新代码写回 App Target 内联 Network 源。
