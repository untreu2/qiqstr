extension AuthTermsText {
    static let markdownTR = #"""
    # Gizlilik Politikası ve Kullanım Koşulları

    Bu metin kolaylık sağlamak amacıyla yapılmış bir çeviridir. İngilizce sürümle bu çeviri arasında fark olması halinde İngilizce sürüm geçerlidir.

    **Uygulama:** qiqstr for iOS — Nostr İstemcisi
    **Geliştirici:** emir yorulmaz
    **Yürürlük Tarihi:** 13 Kasım 2026

    ---

    ## Gizlilik Politikası

    ### Genel Bakış

    qiqstr, geliştiricinin kontrol ettiği sunucularda hiçbir kişisel bilgiyi toplamaz, işlemez veya saklamaz. Geliştirici, Uygulama için herhangi bir sunucu işletmez ve cihazınızdaki verilere erişimi yoktur. Hesabınız, yalnızca sizin elinizde bulunan bir kriptografik anahtar çiftidir.

    Uygulama, Nostr ağı için bir istemcidir. Çalışabilmek için cihazınızdan doğrudan, aşağıda listelenen üçüncü tarafların işlettiği hizmetlere bağlanır. Bu hizmetler bu politikanın kapsamında değildir ve kendi koşulları ile gizlilik uygulamaları vardır.

    ---

    ### Toplamadığımız Bilgiler

    qiqstr şunları toplamaz:

    - Adınızı, e-posta adresinizi veya kişisel olarak tanımlanabilir herhangi bir bilgiyi
    - Konum verilerinizi
    - Özel anahtarınızı veya kurtarma ifadenizi (seed phrase) — bunlar cihazınızdan asla ayrılmaz
    - Geliştiriciye gönderilen kullanım analizlerini veya çökme raporlarını
    - Reklam, izleme veya profilleme amaçlı herhangi bir veriyi

    ---

    ### Uygulamanın Bağlandığı Hizmetler

    Bağlandığınız her hizmet IP adresinizi görebilir. Ayrıca:

    - **Nostr relay'leri.** Varsayılan olarak relay.damus.io, nos.lol, relay.primal.net ve vitor.nostr1.com; bunlara ek olarak sizin eklediğiniz relay'ler, takip ettiğiniz kişilerin kullandığı relay'ler ve herkese açık keşif, arama ve dizin relay'leri. Bunlar açık anahtarınızı, isteklerinizi ve yayınladığınız her şeyi alır. Notlar, tepkiler, yeniden paylaşımlar, takipler, profil bilgileri ve zap makbuzları herkese açıktır ve relay'ler tarafından süresiz olarak saklanabilir ve yeniden dağıtılabilir.
    - **Primal önbellek hizmeti (cache2.primal.net).** Keşfet, trend içerikler ve öneriler için kullanılır. Sonuçların kişiselleştirilebilmesi için açık anahtarınızı alır.
    - **nostr.wine.** Trend içerikler ve arama için kullanılır. Arama sorgularınızı alır.
    - **Medya sunucuları (blossom.primal.net ve nostr.download).** Eklediğiniz fotoğraf ve videolar buralara yüklenir. Herkese açık notlardaki medyayı, bağlantıya sahip olan herkes açabilir. Doğrudan mesajlardaki medya, yüklenmeden önce cihazınızda şifrelenir.
    - **Notlarda bağlantısı verilen web siteleri.** Bağlantı önizlemeleri, görseller ve videolar doğrudan bunları barındıran sitelerden yüklenir.
    - **Cüzdanınız.** Nostr Wallet Connect ile bir cüzdan bağlarsanız, ödeme istekleri bağlantınızda belirtilen relay üzerinden cüzdana gönderilir. Bir zap gönderdiğinizde veya bir Lightning adresine ödeme yaptığınızda Uygulama, alıcının Lightning sağlayıcısıyla iletişime geçer. Bir Cashu token'ı bozdurmak, token'ı çıkaran mint ile iletişime geçer.
    - **Kimlik sağlayıcıları.** Bir Nostr adresini (NIP-05) doğrulamak, o adresteki alan adıyla iletişime geçer.
    - **mempool.space.** Bitcoin fiyatlarını yerel para biriminizde göstermek için kullanılır. Bunu Ayarlar'dan kapatabilirsiniz.

    ---

    ### Cihazınızda Saklanan Veriler

    - Özel anahtarlarınız ve cüzdan bağlantınız iOS Anahtar Zinciri'nde (Keychain) tutulur.
    - Doğrudan mesajlar, cihazınızda şifreli bir veritabanında saklanır.
    - Notlar, profiller ve medya, Uygulama hızlı çalışsın diye önbelleğe alınır. Bu önbelleği Ayarlar'dan temizleyebilirsiniz.
    - Tercihleriniz, taslaklarınız, sessize alma listeniz ve gizlenen gönderileriniz yerel olarak saklanır.

    ---

    ### Verilerinizi Silme

    Hesabınızı istediğiniz zaman **Ayarlar > Hesabı Sil** bölümünden silebilirsiniz. Uygulama bunun ardından relay'lerden olaylarınızı silmelerini (NIP-09) ve hesabınızı kaldırmalarını (NIP-62 kaybolma isteği) ister; ayrıca hesabın anahtarlarını, mesajlarını, cüzdan bağlantısını ve diğer verilerini cihazınızdan siler.

    Relay'ler üçüncü tarafların işlettiği sistemlerdir. Geliştirici, silme isteklerine uymaları için onları zorlayamaz ve başkalarının zaten kopyaladığı içerik geri alınamaz. Oturumu kapatmak, herhangi bir silme isteği göndermeden anahtarınızı cihazdan kaldırır.

    ---

    ### Çocuklar

    Uygulama çocuklara yönelik değildir. App Store'daki Uygulama derecelendirmesinin ve ülkenizin yasalarının belirlediği asgari yaşı karşılamalısınız.

    ---

    ## Kullanım Koşulları

    ### 1. Koşulların Kabulü

    qiqstr'yi ("Uygulama") indirerek, yükleyerek veya kullanarak bu Kullanım Koşulları'na bağlı olmayı kabul etmiş olursunuz. Kabul etmiyorsanız Uygulamayı kullanmayın.

    ---

    ### 2. Uygulamanın Tanımı

    qiqstr, aşağıdakileri yapmanıza olanak tanıyan ücretsiz ve açık kaynaklı bir Nostr protokolü istemcisidir:

    - Nostr ağında notlar, makaleler ve diğer içerikleri yayınlamak ve okumak
    - Diğer kullanıcıları takip etmek ve sosyal grafiğinizi yönetmek
    - Uçtan uca şifreli doğrudan mesajlar göndermek ve almak
    - İçeriklere tepki vermek, yeniden paylaşmak ve alıntılamak
    - Nostr Wallet Connect (NWC) ile bağladığınız bir cüzdan üzerinden Bitcoin Lightning ödemeleri göndermek ve almak
    - Nostr ağındaki kimliğiniz için kriptografik anahtar çiftlerini yönetmek

    Uygulama [MIT Lisansı](https://github.com/untreu2/qiqstr/blob/master/LICENSE) kapsamında yayımlanmıştır. Kaynak kodu herkese açıktır.

    ---

    ### 3. Nostr Protokolü ve Merkeziyetsizlik

    qiqstr, merkeziyetsiz ve açık bir ağ olan **Nostr protokolü** için bir istemcidir:

    - **Merkezi sunucu yoktur.** İçerik, bağımsız olarak işletilen relay'lere yayınlanır ve oradan alınır. Geliştirici bu relay'leri işletmez veya kontrol etmez.
    - **Geliştiricinin tuttuğu hesap yoktur.** Nostr'daki kimliğiniz yalnızca sizin oluşturduğunuz ve kontrol ettiğiniz bir kriptografik anahtar çiftiyle belirlenir.
    - **Moderasyon Uygulama içinde gerçekleşir.** Geliştirici, işletmediği relay'lerden veri silemez. Bu nedenle Uygulama gösterdiklerini filtreler ve size 7. Bölüm'de açıklanan araçları sunar.
    - **İçerik varsayılan olarak herkese açıktır.** Notlar, tepkiler, yeniden paylaşımlar ve profil üst verileri, şifrelenmedikçe yayınladığınız relay'lere erişimi olan herkes tarafından görülebilir.

    ---

    ### 4. Kriptografik Anahtarlarınız

    Nostr kimliğiniz tamamen özel anahtarınız (`nsec`) tarafından kontrol edilir. Şunlardan yalnızca siz sorumlusunuz:

    - Özel anahtarınızı güvenli biçimde oluşturmak, saklamak ve yedeklemek.
    - Özel anahtarınızla, sizin tarafınızdan veya ona erişen herhangi bir üçüncü taraf tarafından yapılan tüm işlemler.
    - **Özel anahtarınızı kaybederseniz kimliğinizin kurtarılamayacağını** anlamak — ne geliştirici ne de herhangi bir relay işletmecisi bunu yapabilir.
    - **Özel anahtarınız ele geçirilirse**, ona sahip olan herhangi bir tarafın Nostr ağında sizin adınıza hareket edebileceğini anlamak.

    Uygulama, özel anahtarınızı cihazınızda işletim sisteminin sağladığı güvenli depolama ile yerel olarak saklar. Geliştirici özel anahtarınıza asla erişemez.

    ---

    ### 5. Bitcoin ve Lightning Ödemeleri

    qiqstr, Nostr Wallet Connect (NWC) protokolü üzerinden Bitcoin Lightning ödemeleri gönderebilir ve talep edebilir. Cüzdan özelliklerini kullanarak şunları kabul edersiniz:

    - Uygulama, sizin yapılandırdığınız harici bir cüzdan hizmetini veya düğümü uzaktan kontrol eder. Geliştirici herhangi bir cüzdan hizmeti işletmez; paranızı tutmaz, kontrol etmez ve ona erişimi yoktur.
    - **Zap'ler isteğe bağlı hediyelerdir.** Zap, cüzdanınızdan başka bir kişinin cüzdanına doğrudan gönderilen isteğe bağlı bir ödemedir. Zap'ler Uygulamada herhangi bir içeriğin, özelliğin veya hizmetin kilidini açmaz ve geliştirici bunlardan hiçbir pay almaz.
    - Bitcoin ve Lightning Network işlemleri **geri alınamaz**. Onaylamadan önce tüm ödeme bilgilerini doğrulayın.
    - Geliştirici bir finans kuruluşu, para hizmetleri işletmesi veya ödeme işlemcisi değildir.
    - Bulunduğunuz yargı bölgesinde kripto para kullanımına ilişkin geçerli yasalara uyumdan yalnızca siz sorumlusunuz.
    - Geliştirici; hatalı işlemler, cüzdan hizmeti arızaları veya ağ hataları nedeniyle oluşan hiçbir para kaybından sorumlu değildir.

    ---

    ### 6. Cashu Token'ları

    Uygulama, yapıştırdığınız veya taradığınız bir Cashu token'ını bozdurabilir. Token, onu çıkaran mint ile takas edilir ve bağlı Lightning cüzdanınıza ödenir. Bu özelliği kullanarak şunları kabul edersiniz:

    - **Mint'ler bağımsız üçüncü taraflardır.** Geliştiricinin herhangi bir mint ile bağlantısı yoktur; onları kontrol etmez ve onlardan sorumlu değildir.
    - **Bozdurma başarısız olabilir.** Ödeme tamamlanmazsa, siz yeniden deneyene kadar değer cihazınızdaki Uygulamada kalır. Yedeklenmez; Uygulamayı veya verilerini silerseniz kaybolur.
    - Geliştirici; bir mint'in, başarısız bir bozdurmanın veya cihazınızdaki verilerin kaybının neden olduğu hiçbir para kaybından sorumlu değildir.

    ---

    ### 7. Yasaklı Davranışlar ve Moderasyon

    **qiqstr, sakıncalı içeriğe ve kötüye kullanan kullanıcılara karşı sıfır tolerans uygular.**

    qiqstr'yi kullanarak Uygulamayı şunlar için kullanmamayı kabul edersiniz:

    - Geçerli yasalara göre yasa dışı olan içeriği yayınlamak, dağıtmak veya bunun kolaylaştırılmasına yardım etmek.
    - Sakıncalı içerik göndermek; buna şunlar dahildir ancak bunlarla sınırlı değildir: (i) cinsel içerikli materyaller; (ii) müstehcen, itibar zedeleyici, iftira niteliğinde, şiddet içeren veya yasa dışı içerik; (iii) telif hakkı, ticari marka veya gizlilik hakları dahil olmak üzere herhangi bir üçüncü tarafın haklarını ihlal eden içerik; (iv) yasa dışı veya düzenlemeye tabi maddelerin, tütün ürünlerinin, mühimmatın veya ateşli silahların kullanımını ya da satışını teşvik eden içerik; (v) kumarla ilgili yasa dışı içerik.
    - Diğer kişileri taciz etmek, tehdit etmek veya onlara zarar vermek.
    - Herhangi bir kişiyi veya kuruluşu taklit etmek.
    - Kötü amaçlı yazılım, spam veya diğer zararlı içerikleri dağıtmak.
    - Nostr relay'lerinin veya diğer ağ altyapısının işleyişini bozmaya ya da düşürmeye çalışmak.

    Uygulamayı güvenli tutmak için:

    - **Bildirme.** Herhangi bir notu, profili, sohbeti, canlı yayını, sohbet mesajını veya makaleyi menüsünden bildirebilirsiniz. Bildirilen içerik sizin için hemen gizlenir.
    - **Engelleme.** Herhangi bir kullanıcıyı sessize alabilirsiniz. Sessize alınan bir kullanıcının notları, yanıtları, mesajları ve bildirimleri artık sizde görünmez.
    - **Filtreleme.** Hassas olarak işaretlenen gönderiler bir uyarının arkasında gizlenir ve spam filtreleri varsayılan olarak açıktır.
    - **24 saat içinde inceleme.** Geliştirici, 15. Bölüm'deki iletişim adresi üzerinden aldığı bildirimleri ve şikâyetleri 24 saat içinde inceler; kuralları ihlal eden içeriği ve sorumlu hesapları, kontrol ettiği Uygulama bölümlerinden kaldırır.

    Bu koşulları ihlal ederseniz Uygulamayı kullanma hakkınız derhal sona erer.

    ---

    ### 8. App Store Koşulları

    qiqstr'yi Apple'ın App Store'undan indirdiyseniz, kullanımınız ayrıca Apple Media Services Şartları ve Koşulları dahil olmak üzere Apple'ın koşullarına tabidir. Apple, Uygulamadan veya içeriğinden sorumlu değildir ve Uygulamaya bakım veya destek sağlama yükümlülüğü yoktur.

    ---

    ### 9. Açık Kaynak ve Fikri Mülkiyet

    qiqstr, **MIT Lisansı** altında lisanslanmış açık kaynaklı bir yazılımdır. MIT Lisansı'na uygun olarak yazılımı kullanmakta, kopyalamakta, değiştirmekte, birleştirmekte, yayımlamakta, dağıtmakta, alt lisanslamakta ve/veya kopyalarını satmakta özgürsünüz.

    qiqstr adı, logosu ve ilgili marka unsurları geliştiricinin mülkiyetindedir. MIT Lisansı, önceden yazılı izin alınmadan bunların markalama veya tavsiye amaçlarıyla kullanılması için hak vermez.

    ---

    ### 10. Garanti Reddi

    UYGULAMA, TİCARİ ELVERİŞLİLİK, BELİRLİ BİR AMACA UYGUNLUK VE HAK İHLALİ OLMAMASI GARANTİLERİ DAHİL OLMAK ANCAK BUNLARLA SINIRLI OLMAMAK ÜZERE, AÇIK VEYA ZIMNİ HİÇBİR GARANTİ VERİLMEKSİZİN "OLDUĞU GİBİ" VE "MEVCUT OLDUĞU ŞEKLİYLE" SUNULMAKTADIR.

    GELİŞTİRİCİ ŞUNLARI GARANTİ ETMEZ:
    - UYGULAMANIN KESİNTİSİZ, HATASIZ VEYA GÜVENLİ OLACAĞINI.
    - HERHANGİ BİR KUSURUN GİDERİLECEĞİNİ.
    - UYGULAMANIN VEYA ONU KULLANIMA SUNAN SUNUCULARIN VİRÜSLERDEN VEYA DİĞER ZARARLI BİLEŞENLERDEN ARINDIRILMIŞ OLDUĞUNU.

    ---

    ### 11. Sorumluluğun Sınırlandırılması

    GEÇERLİ YASALARIN İZİN VERDİĞİ AZAMİ ÖLÇÜDE GELİŞTİRİCİ, AŞAĞIDAKİLER DAHİL OLMAK ANCAK BUNLARLA SINIRLI OLMAMAK ÜZERE, DOLAYLI, ARIZİ, ÖZEL, SONUÇSAL VEYA CEZAİ NİTELİKTEKİ HİÇBİR ZARARDAN SORUMLU OLMAYACAKTIR:

    - PARA, BİTCOİN VEYA DİĞER DİJİTAL VARLIKLARIN KAYBI.
    - VERİ VEYA ÖZEL ANAHTAR KAYBI.
    - HESABINIZA VEYA ANAHTARLARINIZA YETKİSİZ ERİŞİM.
    - UYGULAMAYI KULLANMANIZDAN VEYA KULLANAMAMANIZDAN KAYNAKLANAN HERHANGİ BİR ZARAR.

    BU SINIRLAMA, SORUMLULUK TEORİSİNDEN BAĞIMSIZ OLARAK VE GELİŞTİRİCİYE BÖYLE ZARARLARIN OLASILIĞI BİLDİRİLMİŞ OLSA DAHİ GEÇERLİDİR.

    ---

    ### 12. Tazminat

    Uygulamayı kullanmanızdan, bu Koşullar'ı ihlal etmenizden veya başka bir tarafın herhangi bir hakkını ihlal etmenizden kaynaklanan ya da bunlarla herhangi bir şekilde bağlantılı her türlü talep, yükümlülük, zarar, kayıp ve masraftan (makul hukuki ücretler dahil) geliştiriciyi tazmin etmeyi ve sorumsuz tutmayı kabul edersiniz.

    ---

    ### 13. Bu Koşullardaki Değişiklikler

    Geliştirici, bu Koşullar'ı istediği zaman değiştirme hakkını saklı tutar. Değişiklikler, bu belgenin başındaki "Yürürlük Tarihi" güncellenerek yansıtılacaktır. Değişikliklerden sonra Uygulamayı kullanmaya devam etmek, güncellenmiş Koşullar'ın kabul edildiği anlamına gelir.

    ---

    ### 14. Uygulanacak Hukuk

    Bu Koşullar, geçerli hukuka tabidir ve ona göre yorumlanır. Bu Koşullar kapsamında ortaya çıkan her türlü uyuşmazlık, yasaların izin verdiği ölçüde geliştiricinin ikamet ettiği yargı bölgesinde çözülecektir.

    ---

    ### 15. İletişim

    Bir içeriği veya kullanıcıyı bildirmek, verilerinizle ilgili soru sormak ya da bu Gizlilik Politikası veya Kullanım Koşulları hakkında herhangi bir sorunuz için geliştiriciyle [github.com/untreu2/qiqstr/issues](https://github.com/untreu2/qiqstr/issues) adresinden iletişime geçin. Aynı bağlantıya Uygulamada **Ayarlar > Destekle iletişime geç** bölümünden de ulaşabilirsiniz.
    """#
}
