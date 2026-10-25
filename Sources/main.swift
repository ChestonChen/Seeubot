import AppKit

if CommandLine.arguments.contains("--stats") {
    let stats = SessionCollector().collect()
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let d = try? enc.encode(stats), let s = String(data: d, encoding: .utf8) {
        print(s)
    }
    exit(0)
}


MainActor.assumeIsolated{
let app=NSApplication.shared
let delegate=AppDelegate() //AppDelegate是一个类
app.delegate=delegate
app.run()
}

//创建一个app和代理实例，并设置代理给app然后启动
//a.delegate=b ,a委托给b干活（a把他的活交给b干了），b完成任务后通知a（或者a不关心就直接return）
//run后app把启动工作委托给app.delegate执行（框架指定），启动函数是我们自定义的
