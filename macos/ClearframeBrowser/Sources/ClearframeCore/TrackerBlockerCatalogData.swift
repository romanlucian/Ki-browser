import Foundation

/// The maintainable, compile-time tracker list. Like the AI catalog it is
/// reviewed, tested, and shipped with the app rather than downloaded.
///
/// Inclusion policy: a domain belongs here only when its primary third-party
/// function is ad delivery or audience measurement — exchanges, ad servers,
/// measurement beacons, session replay, and paid content-recommendation
/// widgets. Deliberately excluded, because blocking them breaks ordinary
/// browsing rather than reducing tracking: tag managers (`googletagmanager.com`),
/// consent platforms, login and social SDKs (`connect.facebook.net`), general
/// CDNs, affiliate link redirectors, bot/fraud protection, error and
/// performance monitoring, A/B testing, on-site personalisation, chat, and
/// support widgets. Entries a reviewer could not confirm are left out; a
/// shorter honest list is better than a padded one.
///
/// This is first-party editorial work. No EasyList or other third-party
/// blocklist was imported or converted.
enum TrackerBlockerCatalogData {
    /// Sorted so the generated rule list is byte-stable across launches. Tests
    /// enforce the sort, the character set, and the absence of duplicates.
    static let domains: [String] = curated.sorted()

    private static let curated: [String] =
        googleAdvertising
        + adobeAdvertising
        + exchangesAndAdServers
        + nativeAdWidgets
        + videoAdvertising
        + adVerification
        + audienceMeasurement
        + sessionReplay
        + mobileAttribution
        + audienceDataAndIdentity
        + socialAdPixels

    // Google ad serving and measurement. `googletagmanager.com` is excluded:
    // it is a tag container many sites use for non-advertising code as well.
    private static let googleAdvertising = [
        "2mdn.net",
        "app-measurement.com",
        "doubleclick.net",
        "google-analytics.com",
        "googleadservices.com",
        "googlesyndication.com",
        "googletagservices.com"
    ]

    // Adobe advertising and analytics collection. `adobedtm.com` is excluded as
    // a tag manager.
    private static let adobeAdvertising = [
        "2o7.net",
        "demdex.net",
        "everesttech.net",
        "omtrdc.net"
    ]

    // Ad exchanges, supply- and demand-side platforms, and ad servers.
    private static let exchangesAndAdServers = [
        "33across.com",
        "360yield.com",
        "3lift.com",
        "adap.tv",
        "adblade.com",
        "adcash.com",
        "adcolony.com",
        "adform.net",
        "adition.com",
        "adnow.com",
        "adnxs-simple.com",
        "adnxs.com",
        "adocean.pl",
        "adriver.ru",
        "adroll.com",
        "adsrvr.org",
        "adsterra.com",
        "adsymptotic.com",
        "adtechus.com",
        "advertising.com",
        "adyoulike.com",
        "adzerk.net",
        "alimama.com",
        "amazon-adsystem.com",
        "appnexus.com",
        "applovin.com",
        "atdmt.com",
        "bidr.io",
        "bidswitch.net",
        "bidvertiser.com",
        "btrll.com",
        "buysellads.com",
        "carbonads.net",
        "casalemedia.com",
        "chartboost.com",
        "clickadu.com",
        "connatix.com",
        "contextweb.com",
        "conversantmedia.com",
        "criteo.com",
        "criteo.net",
        "districtm.io",
        "dotomi.com",
        "e-planning.net",
        "emxdgt.com",
        "exoclick.com",
        "exponential.com",
        "fastclick.net",
        "flashtalking.com",
        "fyber.com",
        "gumgum.com",
        "hilltopads.net",
        "improvedigital.com",
        "indexww.com",
        "infolinks.com",
        "inmobi.com",
        "juicyads.com",
        "kargo.com",
        "liftoff.io",
        "lijit.com",
        "loopme.me",
        "magnite.com",
        "mathtag.com",
        "media.net",
        "mediaplex.com",
        "microad.jp",
        "mobfox.com",
        "mopub.com",
        "msads.net",
        "nextroll.com",
        "onetag-sys.com",
        "openx.net",
        "popads.net",
        "popcash.net",
        "primis.tech",
        "propellerads.com",
        "pubmatic.com",
        "pubnative.net",
        "revsci.net",
        "rfihub.com",
        "richaudience.com",
        "rtbhouse.com",
        "rubiconproject.com",
        "sascdn.com",
        "seedtag.com",
        "serving-sys.com",
        "sharethrough.com",
        "sitescout.com",
        "sizmek.com",
        "smaato.com",
        "smartadserver.com",
        "sonobi.com",
        "sovrn.com",
        "stackadapt.com",
        "startapp.com",
        "supersonicads.com",
        "tanx.com",
        "tapjoy.com",
        "themediagrid.com",
        "trafficjunky.com",
        "trafficstars.com",
        "tribalfusion.com",
        "triplelift.com",
        "w55c.net",
        "yieldlab.net",
        "yieldmanager.com",
        "yieldmo.com",
        "zedo.com"
    ]

    // Paid "recommended for you" widgets and native ad networks.
    private static let nativeAdWidgets = [
        "adthrive.com",
        "content.ad",
        "dianomi.com",
        "engageya.com",
        "ligatus.com",
        "mediavine.com",
        "mgid.com",
        "nativo.com",
        "outbrain.com",
        "plista.com",
        "revcontent.com",
        "taboola.com",
        "zemanta.com",
        "zergnet.com"
    ]

    // Video and connected-TV ad serving.
    private static let videoAdvertising = [
        "freewheel.tv",
        "fwmrm.net",
        "innovid.com",
        "springserve.com",
        "spotx.tv",
        "spotxchange.com",
        "teads.tv",
        "tremorhub.com",
        "unrulymedia.com"
    ]

    // Ad verification and viewability measurement.
    private static let adVerification = [
        "adsafeprotected.com",
        "doubleverify.com",
        "moatads.com"
    ]

    // Audience measurement and analytics beacons.
    private static let audienceMeasurement = [
        "amplitude.com",
        "audienceproject.com",
        "chartbeat.com",
        "chartbeat.net",
        "cnzz.com",
        "cxense.com",
        "gemius.pl",
        "getclicky.com",
        "heapanalytics.com",
        "histats.com",
        "hs-analytics.net",
        "imrworldwide.com",
        "ioam.de",
        "kissmetrics.com",
        "miaozhen.com",
        "mixpanel.com",
        "mktoresp.com",
        "mmstat.com",
        "parsely.com",
        "quantcount.com",
        "quantserve.com",
        "scorecardresearch.com",
        "statcounter.com",
        "umeng.com",
        "voicefive.com",
        "woopra.com"
    ]

    // Session replay and on-page behaviour recording.
    private static let sessionReplay = [
        "clarity.ms",
        "clicktale.net",
        "contentsquare.net",
        "crazyegg.com",
        "decibelinsight.com",
        "fullstory.com",
        "hotjar.com",
        "inspectlet.com",
        "luckyorange.com",
        "mouseflow.com",
        "quantummetric.com",
        "sessioncam.com",
        "smartlook.com"
    ]

    // Mobile install and campaign attribution services that also run on the web.
    private static let mobileAttribution = [
        "adjust.com",
        "appsflyer.com",
        "branch.io",
        "flurry.com",
        "kochava.com",
        "singular.net"
    ]

    // Audience data platforms and advertising identity graphs.
    private static let audienceDataAndIdentity = [
        "agkn.com",
        "bizographics.com",
        "bluekai.com",
        "crwdcntrl.net",
        "demandbase.com",
        "exelator.com",
        "eyeota.net",
        "id5-sync.com",
        "krxd.net",
        "liveramp.com",
        "lotame.com",
        "permutive.com",
        "rlcdn.com",
        "tapad.com"
    ]

    // Social-platform ad conversion pixels served from advertising-only hosts.
    // Login and share SDKs such as `connect.facebook.net` stay out.
    private static let socialAdPixels = [
        "ads-twitter.com"
    ]
}
