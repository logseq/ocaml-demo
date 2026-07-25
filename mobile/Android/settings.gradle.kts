pluginManagement {
    val pluginPath = File.createTempFile("skip-plugin-path", ".tmp")
    val skipPluginResult = providers.exec {
        commandLine(
            "/bin/sh",
            "-c",
            "skip plugin --prebuild --package-path '${settings.rootDir.parent}' --plugin-ref '${pluginPath.absolutePath}'"
        )
        environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
    }
    print(skipPluginResult.standardOutput.asText.get())
    print(skipPluginResult.standardError.asText.get())
    includeBuild(pluginPath.readText()) {
        name = "skip-plugins"
    }
}

plugins {
    id("skip-plugin") apply true
}
