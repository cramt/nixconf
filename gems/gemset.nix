{
  ast = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "04nc8x27hlzlrr5c2gn7mar4vdr0apw5xg22wp6m8dx3wqr04a0y";
      type = "gem";
    };
    version = "2.4.2";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0b4qsi8gay7ncmigr0pnbxyb17y3h8kavdyhsh7nrlqwr35vb60q";
      type = "gem";
    };
    version = "2.7.2";
  };
  language_server-protocol = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0gvb1j8xsqxms9mww01rmdl78zkd72zgxaap56bhv8j45z05hp1x";
      type = "gem";
    };
    version = "3.17.0.3";
  };
  logger = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0lwncq2rf8gm79g2rcnnyzs26ma1f4wnfjm6gs4zf2wlsdz5in9s";
      type = "gem";
    };
    version = "1.6.1";
  };
  parallel = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1vy7sjs2pgz4i96v5yk9b7aafbffnvq7nn419fgvw55qlavsnsyq";
      type = "gem";
    };
    version = "1.26.3";
  };
  parser = {
    dependencies = ["ast" "racc"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1cqs31cyg2zp8yx2zzm3zkih0j93q870wasbviy2w343nxqvn3pk";
      type = "gem";
    };
    version = "3.3.5.0";
  };
  prism = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0w6v6hc7pk7hrsvkpr1jkk55syna94im7yzmjim0lly2aadwn86c";
      type = "gem";
    };
    version = "1.0.0";
  };
  racc = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0byn0c9nkahsl93y9ln5bysq4j31q8xkf2ws42swighxd4lnjzsa";
      type = "gem";
    };
    version = "1.8.1";
  };
  rainbow = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0smwg4mii0fm38pyb5fddbmrdpifwv22zv3d3px2xx497am93503";
      type = "gem";
    };
    version = "3.1.1";
  };
  rbs = {
    dependencies = ["logger"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0lph27fb8n2bwnqaqy0xm1jwjar7ljqrcq16ajhylh0yvfhfwqpj";
      type = "gem";
    };
    version = "3.5.3";
  };
  regexp_parser = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0ik40vcv7mqigsfpqpca36hpmnx0536xa825ai5qlkv3mmkyf9ss";
      type = "gem";
    };
    version = "2.9.2";
  };
  rubocop = {
    dependencies = ["json" "language_server-protocol" "parallel" "parser" "rainbow" "regexp_parser" "rubocop-ast" "ruby-progressbar" "unicode-display_width"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1rsyxrl647bz49gpa4flh8igg6wy7qxyh2jrp01x0kqnn5iw4y86";
      type = "gem";
    };
    version = "1.66.1";
  };
  rubocop-ast = {
    dependencies = ["parser"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "03zywfpm4540q6hw8srhi8pzp0gg51w65ir8jkaw58vk3j31w820";
      type = "gem";
    };
    version = "1.32.3";
  };
  ruby-lsp = {
    dependencies = ["language_server-protocol" "prism" "rbs" "sorbet-runtime"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "12vrkd5650m7rfh23lzhmp6384y29adxlhmsq5ll6d7ysc6v8iv1";
      type = "gem";
    };
    version = "0.17.17";
  };
  ruby-progressbar = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0cwvyb7j47m7wihpfaq7rc47zwwx9k4v7iqd9s1xch5nm53rrz40";
      type = "gem";
    };
    version = "1.13.0";
  };
  sorbet-runtime = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0j8wq78778p9wrx1lwb23zd1f6cyh2v8aidzf5w0sw91dgy4jmg3";
      type = "gem";
    };
    version = "0.5.11566";
  };
  unicode-display_width = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0nkz7fadlrdbkf37m0x7sw8bnz8r355q3vwcfb9f9md6pds9h9qj";
      type = "gem";
    };
    version = "2.6.0";
  };
}