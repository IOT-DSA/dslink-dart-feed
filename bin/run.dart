import "dart:async";
import "dart:convert";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

import "package:dart_feed/dart_feed.dart";
import "package:xml/xml.dart";
import "package:crypto/crypto.dart";

LinkProvider link;

main(List<String> args) async {
  link = new LinkProvider(args, "Feed-", nodes: {
    "Add_Feed": {
      r"$name": "Add Feed",
      r"$params": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "url",
          "type": "string"
        }
      ],
      r"$result": "values",
      r"$invokable": "write",
      r"$is": "addFeed"
    }
  }, profiles: {
    "feed": (String path) => new FeedNode(path),
    "addFeed": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) {
      if (params["name"] == null || params["url"] == null || params["name"].isEmpty) {
        return;
      }

      String name = params["name"];
      String url = params["url"];

      link.addNode("/${name}", {
        r"$is": "feed",
        r"$feed_url": url
      });

      link.save();
    }),
    "remove": (String path) => new DeleteActionNode.forParent(path, link.provider)
  }, autoInitialize: false);
  link.init();
  link.connect();
}

class FeedNode extends SimpleNode {
  Timer timer;

  FeedNode(String path) : super(path);

  bool syncing = false;

  @override
  onCreated() async {
    createChild("Remove", {
      r"$invokable": "write",
      r"$result": "values",
      r"$is": "remove"
    });

    if (url == null) {
      return;
    }

    timer = Scheduler.every(Interval.FIVE_SECONDS, () async {
      if (syncing) {
        return;
      }

      try {
        syncing = true;
        await update();
      } catch (e) {
        print(e);
      } finally {
        syncing = false;
      }
    });

    await update();
  }

  String get url => configs[r"$feed_url"];

  update() async {
    var uri = Uri.parse(url);
    var feed = await Feed.fromUri(uri);
    List<String> guids = feed.items.map((x) => x.guid.guid).toSet().toList();
    children.values
      .where((x) => x.configs[r"$invokable"] == null)
      .where((x) => x.configs[r"$guid"] != null)
      .where((x) {
      return !guids.contains(x.configs[r"$guid"]);
    }).map((SimpleNode x) => x.path).toList().forEach(link.removeNode);
    for (Item item in feed.items) {
      var guid = item.guid.guid;
      var hashuid = createHashString(guid);
      if (children.keys.contains(hashuid)) {
        continue;
      }

      String author = item.author;
      Iterable<XmlElement> creator = item.xml.findAllElements("dc:creator");

      if (author == null || author.isEmpty) {
        if (creator != null && creator.isNotEmpty) {
          author = creator.first.text.trim();
        }
      }

      SimpleNode node = link.addNode("${path}/${hashuid}", {
        r"$name": item.title,
        "Title": {
          r"$type": "string",
          "?value": item.title
        },
        "Author": {
          r"$type": "string",
          "?value": author
        },
        "Published": {
          r"$type": "string",
          "?value": item.pubDate.toIso8601String()
        },
        "Description": {
          r"$type": "string",
          "?value": item.description
        },
        "Url": {
          r"$type": "string",
          "?value": item.link.toString()
        },
        r"$guid": item.guid.guid
      });
      node.serializable = false;
    }
  }

  @override
  onRemoving() {
    if (timer != null && timer.isActive) {
      timer.cancel();
    }
  }
}

String createHashString(String name) {
  var hash = new SHA1();
  hash.add(UTF8.encode(name));
  var result = hash.close();
  return CryptoUtils.bytesToHex(result);
}

