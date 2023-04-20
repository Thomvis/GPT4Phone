import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("This app is only there to have a valid value for the TEST_TARGET setting of the UI Tests. This app is not actually launched.")
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
