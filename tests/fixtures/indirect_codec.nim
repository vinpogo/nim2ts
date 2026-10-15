import codec

let text = encode(sample())
echo text
echo encode(decode(text, Everything)) == text
echo encode(@[item()])
echo encode(someItem())
echo encode(Wrapped(item()))
