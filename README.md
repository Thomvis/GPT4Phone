# GPT4Phone
Let GPT-4 control your iPhone (or a simulator). Accompanying blog post: https://www.thomasvisser.me/2023/05/04/gpt4phone/.

[![Example video](https://img.youtube.com/vi/2TQ4u9S_PrU/hqdefault.jpg)](https://youtu.be/2TQ4u9S_PrU)

## Usage
Clone the repo on your machine, make sure you have Xcode installed and then execute the following command from the project’s directory:

```
OPENAI_API_KEY=<Your OpenAI Key> TASK=<Task Description> ./run
```

By default it runs on the iPhone 14 simulator, but you can set the `DESTINATION` env variable to [specify](https://mokacoding.com/blog/xcodebuild-destination-options/) a different device. For example, add `DESTINATION="platform=iOS,name=<Phone name>"` to run it on your real device.

## Known issues
- On the home screen, only apps on the current page can be launched. Work-around: disable all but one page.
