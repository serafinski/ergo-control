import Foundation
import ErgoUSBResearch

exit(USBInspector.run(Array(CommandLine.arguments.dropFirst())))
