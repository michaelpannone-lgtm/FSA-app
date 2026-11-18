import Foundation

/// A keyword rule. Keywords are matched against normalized receipt text
/// (lowercase, punctuation -> spaces). See `TextNormalizer.matches` for matching semantics.
public struct EligibilityRule: Sendable {
    public let category: String
    public let eligibility: Eligibility
    public let keywords: [String]
    /// Added to keyword length when ranking matches. Lets a short but decisive keyword
    /// ("spf") beat a longer generic one ("lotion").
    public let priority: Int

    public init(_ category: String, _ eligibility: Eligibility, _ keywords: [String], priority: Int = 0) {
        self.category = category
        self.eligibility = eligibility
        self.keywords = keywords
        self.priority = priority
    }
}

/// Default rules based on IRS Publication 502 and the 2020 CARES Act (OTC medicine and
/// menstrual products no longer need a prescription). When several keywords match,
/// the longest keyword wins, so "diaper rash cream" beats "diaper".
public enum EligibilityRules {
    public static let all: [EligibilityRule] = likely + maybe + notEligible

    static let likely: [EligibilityRule] = [
        EligibilityRule("Prescription", .likely, [
            "rx", "rx#", "prescription", "presc", "pharmacy rx", "copay", "co pay", "refill"
        ]),
        EligibilityRule("Medical service", .likely, [
            "office visit", "deductible", "coinsurance", "patient resp", "patient balance", "exam", "x ray", "xray",
            "lab", "labs", "lab work", "bloodwork", "vaccin", "immuniz", "flu shot", "physical therapy", "chiropract",
            "acupunct", "counseling", "psychotherapy", "therapy session", "ambulance", "urgent care", "telehealth",
            "dental", "dentist", "prophylaxis", "dental cleaning", "filling", "root canal", "crown", "orthodont",
            "invisalign", "lasik", "eye exam", "vision exam", "hearing test", "mammogra", "ultrasound", "mri",
            "surgery", "anesthes", "consultation", "well visit", "physical exam"
        ]),
        EligibilityRule("OTC medicine (CARES Act)", .likely, [
            "acetaminophen", "acetamin", "apap", "tylenol", "ibuprofen", "ibupro", "ibu", "advil", "motrin",
            "naproxen", "naprox", "aleve", "aspirin", "bayer", "excedrin", "pain rel", "pain reliever", "migraine",
            "allergy", "allerg", "allrgy", "antihistamine", "claritin", "loratadine", "lorat", "zyrtec", "cetirizine",
            "cetiriz", "allegra", "fexofenadine", "fexofen", "xyzal", "benadryl", "diphenhydramine", "diphen",
            "flonase", "nasacort", "fluticasone", "nasal spray", "nasal", "sinus", "saline nasal", "decongest",
            "sudafed", "pseudoephed", "phenyleph", "mucinex", "guaifenesin", "guaif", "dextrometh", "robitussin",
            "delsym", "cough", "throat lozenge", "lozenge", "cough drop", "halls", "chloraseptic", "nyquil", "dayquil",
            "theraflu", "cold and flu", "cold flu", "cold relief", "cold rlf", "cold sore", "abreva", "flu",
            "antacid", "tums", "rolaids", "heartburn", "acid reduc", "acid red", "pepcid", "famotidine", "omeprazole",
            "prilosec", "nexium", "esomeprazole", "lansoprazole", "prevacid", "zantac", "gas relief", "gas x",
            "simethicone", "imodium", "loperamide", "antidiarr", "anti diarr", "pepto", "bismuth", "laxative",
            "laxat", "miralax", "dulcolax", "senna", "stool soft", "colace", "metamucil", "hemorrhoid", "preparation h",
            "hydrocortisone", "hydrocort", "cortizone", "anti itch", "antiitch", "calamine", "benzocaine",
            "lidocaine", "neosporin", "bacitracin", "antibiotic", "antibiot", "first aid oint", "antiseptic", "antisept",
            "hydrogen peroxide", "hydrogen perox", "rubbing alcohol", "isopropyl", "wart", "compound w",
            "athlete", "antifungal", "antifung", "clotrimazole", "clotrim", "terbinafine", "lamisil", "tinactin",
            "monistat", "yeast infection", "lice", "nix lice", "sleep aid", "zzzquil", "unisom", "doxylamine",
            "motion sick", "dramamine", "meclizine", "eye drop", "eye drp", "eye drops", "visine", "systane",
            "refresh tears", "artificial tear", "lubricant eye", "eye wash", "ear drop", "ear wax", "debrox",
            "eczema", "psoriasis", "acne", "benzoyl", "salicylic", "differin", "teething", "orajel", "diaper rash",
            "desitin", "a d ointment", "boudreaux", "children s tylenol", "infants", "pediatric", "fever", "nicotine",
            "nicorette", "nicoderm", "smoking cessation", "medicine", "medication", "tablet", "caplet", "softgel",
            "gelcap", "liquigel", "liqui gel", "mg"
        ]),
        EligibilityRule("Menstrual care (CARES Act)", .likely, [
            "tampon", "tampons", "tampax", "maxi pad", "maxi pads", "pantiliner", "panty liner", "menstrual",
            "period underwear", "period panties", "kotex", "stayfree", "always ultra", "always infinity",
            "always maxi", "playtex sport", "o b tampon", "diva cup", "menstrual cup", "menstrual disc"
        ]),
        EligibilityRule("First aid", .likely, [
            "bandage", "bandaid", "band aid", "bndg", "adhesive pad", "gauze", "first aid", "1st aid", "medical tape",
            "wound", "liquid bandage", "blister", "moleskin", "ace bandage", "elastic bandage", "burn gel",
            "butterfly closure", "steri strip"
        ]),
        EligibilityRule("Medical device / supplies", .likely, [
            "thermometer", "thermom", "blood pressure", "bp monitor", "glucose", "glucometer", "test strip",
            "test strips", "lancet", "insulin", "syringe", "pen needle", "pulse ox", "oximeter", "nebulizer",
            "inhaler", "spacer chamber", "cpap", "heating pad", "cold pack", "hot pack", "ice pack", "hot cold",
            "brace", "knee brace", "wrist brace", "ankle brace", "back brace", "splint", "sling", "crutch", "cane",
            "walker", "wheelchair", "shower chair", "hearing aid", "hearing aid batt", "orthotic", "arch support",
            "pill organizer", "pill box", "pill crusher", "pill cutter", "pill splitter", "nasal aspirator",
            "humidifier wick", "tens unit", "kinesiology tape", "incontinence", "adult brief", "depend", "poise",
            "catheter", "ostomy", "denture", "denture adhesive", "polident", "fixodent", "reading glass",
            "reading glasses", "readers", "magnifier"
        ]),
        EligibilityRule("Vision care", .likely, [
            "contact lens", "contact lenses", "contacts", "acuvue", "dailies", "biofinity", "air optix", "oasys",
            "lens solution", "contact solution", "contact sol", "lens sol", "renu", "opti free", "optifree",
            "clear care", "boston simplus", "eyeglass", "eyeglasses", "prescription glass", "rx glasses",
            "prescription sunglass", "lens case", "frames"
        ]),
        EligibilityRule("Family planning & pregnancy", .likely, [
            "pregnancy test", "pregnan", "ovulation", "fertility", "clearblue", "first response", "condom",
            "condoms", "trojan", "durex", "personal lubricant", "lubricant", "k y", "plan b", "emergency contracep",
            "prenatal", "breast pump", "breast milk", "milk storage", "nursing pad", "breast pad", "lanolin",
            "nipple cream", "breast shield", "flange"
        ]),
        EligibilityRule("Sun protection", .likely, [
            "sunscreen", "sunblock", "spf*", "sun protect"
        ], priority: 10),
        EligibilityRule("Health protection (PPE / testing)", .likely, [
            "hand sanitizer", "hand sanit", "sanitizing wipe", "kn95", "n95", "surgical mask", "face mask",
            "covid test", "antigen test", "rapid test", "binaxnow", "ihealth", "flowflex", "test kit"
        ]),
        EligibilityRule("Store flagged FSA/HSA", .likely, [
            "fsa", "hsa", "fsa eligible", "hsa eligible"
        ], priority: 20)
    ]

    static let maybe: [EligibilityRule] = [
        EligibilityRule("Dual-purpose — may need Letter of Medical Necessity", .maybe, [
            "vitamin", "vitamins", "multivit", "multi vit", "supplement", "probiotic", "fish oil", "omega",
            "melatonin", "protein", "collagen", "electrolyte", "pedialyte", "lactaid", "lactase", "fiber", "glucosamine",
            "turmeric", "magnesium", "calcium", "zinc", "elderberry", "emergen c", "airborne", "massage", "gym",
            "fitness", "weight loss", "weight watchers", "humidifier", "air purif", "compression", "compression sock",
            "insole", "insoles", "dr scholl", "earplug", "ear plug", "mask", "sanitiz", "disinfect", "aloe",
            "after sun", "lip balm", "chapstick", "moisturiz", "eczema lotion", "dandruff", "medicated shampoo",
            "sunglasses", "blue light", "night guard", "mouth guard", "electric toothbrush", "water flosser",
            "waterpik", "foot cream", "callus", "corn remover", "baby thermometer"
        ])
    ]

    static let notEligible: [EligibilityRule] = [
        EligibilityRule("Personal care", .notEligible, [
            "toothpaste", "toothbrush", "floss", "mouthwash", "listerine", "shampoo",
            "conditioner", "deodorant", "antiperspirant", "body wash", "soap", "lotion", "cosmetic", "makeup",
            "mascara", "lipstick", "foundation", "concealer", "nail", "polish", "perfume", "cologne", "fragrance",
            "razor", "shave", "shaving", "hair", "hairspray", "cotton ball", "cotton swab", "q tip", "qtip",
            "tissue", "tissues", "kleenex", "diaper", "diapers", "baby wipe", "wipes", "feminine wash",
            "dry shampoo", "teeth whiten", "whitening", "beauty", "skincare", "face wash", "cleanser"
        ]),
        EligibilityRule("Groceries & household", .notEligible, [
            "milk", "bread", "egg", "eggs", "banana", "bananas", "apple", "apples", "chicken", "beef", "pork",
            "cheese", "yogurt", "butter", "soda", "cola", "coke", "pepsi", "chips", "candy", "chocolate", "snack",
            "snacks", "cereal", "coffee", "tea", "water", "juice", "beer", "wine", "liquor", "produce", "deli",
            "bakery", "grocery", "frozen", "pizza", "fruit", "vegetable", "salad", "gum", "cookies", "crackers",
            "ice cream", "paper towel", "toilet paper", "bath tissue", "detergent", "laundry", "trash bag",
            "cleaner", "bleach", "dish", "sponge", "foil", "batteries", "light bulb"
        ]),
        EligibilityRule("General merchandise", .notEligible, [
            "gift card", "giftcard", "greeting card", "card", "magazine", "toy", "toys", "pet", "dog", "cat",
            "shirt", "socks", "clothing", "apparel", "shoes", "phone", "charger", "cable", "headphone",
            "bag fee", "bag", "bags", "bottle deposit", "crv", "candle", "decor", "seasonal", "stationery",
            "pen", "pens", "tape dispenser", "wrapping", "balloon", "flowers", "plant"
        ])
    ]
}
