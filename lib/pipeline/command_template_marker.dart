/// Line written into every claudart-generated command template's frontmatter.
/// Its presence is how `link` tells its own output apart from a user's file
/// of the same name, so a re-link never overwrites something it didn't write.
const String claudartCommandMarker = 'claudart: generated';

/// Whether [content] was written by claudart (carries the marker), as
/// opposed to a user's own command file that happens to share the name.
bool isClaudartGeneratedCommand(String content) =>
    content.contains(claudartCommandMarker);
