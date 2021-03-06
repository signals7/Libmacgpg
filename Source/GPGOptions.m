/* Copyright © 2002-2006 Mac GPG Project. */
#import "GPGOptions.h"
#import "GPGConf.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "GPGGlobals.h"


@interface GPGOptions (Private)
@property (readonly) NSMutableDictionary *environment;
@property (readonly) NSMutableDictionary *commonDefaults;
- (GPGConf *)gpgConf;
- (GPGConf *)gpgAgentConf;
- (void)valueChanged:(id)value forKey:(NSString *)key inDomain:(GPGOptionsDomain)domain;
- (void)valueChangedNotification:(NSNotification *)notification;
@end


@implementation GPGOptions
NSString *_sharedInstance = nil;
NSString *environmentPlistPath;
NSString *environmentPlistDir;
NSString *commonDefaultsDomain = @"org.gpgtools.common";
NSDictionary *domainKeys;



- (BOOL)autoSave {
	return autoSave;
}
- (void)setAutoSave:(BOOL)value {
	autoSave = value;
	self.gpgConf.autoSave = value;
	self.gpgAgentConf.autoSave = value;
}



- (id)valueForKey:(NSString *)key {
	key = [[self class] standardizedKey:key];
	return [self valueForKey:key inDomain:[self domainForKey:key]];
}
- (void)setValue:(id)value forKey:(NSString *)key {
	key = [[self class] standardizedKey:key];
	[self setValue:value forKey:key inDomain:[self domainForKey:key]];
}

- (id)valueForKey:(NSString *)key inDomain:(GPGOptionsDomain)domain {
	NSObject *value = nil;
	switch (domain) {
		case GPGDomain_gpgConf:
			value = [self.gpgConf valueForKey:key];
			break;
		case GPGDomain_gpgAgentConf:
			value = [self.gpgAgentConf valueForKey:key];
			break;
		case GPGDomain_environment:
			value = [self valueInEnvironmentForKey:key];
			break;
		case GPGDomain_standard:
			value = [self valueInStandardDefaultsForKey:key];
			break;
		case GPGDomain_common:
			value = [self valueInCommonDefaultsForKey:key];
			break;
		case GPGDomain_special:
			value = [self specialValueForKey:key];
			break;
		default:
			[NSException raise:NSInvalidArgumentException format:@"Illegal domain: %i", domain]; 
	}
	return value;
}
- (void)setValue:(id)value forKey:(NSString *)key inDomain:(GPGOptionsDomain)domain {
	switch (domain) {
		case GPGDomain_gpgConf:
			[self.gpgConf setValue:value forKey:key];
			[self valueChanged:value forKey:key inDomain:GPGDomain_gpgConf];
			break;
		case GPGDomain_gpgAgentConf:
			[self.gpgAgentConf setValue:value forKey:key];
			[self valueChanged:value forKey:key inDomain:GPGDomain_gpgAgentConf];
			break;
		case GPGDomain_environment:
			[self setValueInEnvironment:value forKey:key];
			break;
		case GPGDomain_standard:
			[self setValueInStandardDefaults:value forKey:key];
			break;
		case GPGDomain_common:
			[self setValueInCommonDefaults:value forKey:key];
			break;
		case GPGDomain_special:
			[self setSpecialValue:value forKey:key];
			break;
		default:
			[NSException raise:NSInvalidArgumentException format:@"Illegal domain: %i", domain]; 
			break;
	}
}





- (id)specialValueForKey:(NSString *)key {
	if ([key isEqualToString:@"TrustAllKeys"]) {
		return [NSNumber numberWithBool:[[self.gpgConf valueForKey:@"trust-model"] isEqualToString:@"always"]];
	} else if ([key isEqualToString:@"PassphraseCacheTime"]) {
		return [self.gpgAgentConf valueForKey:@"default-cache-ttl"];
	} else if ([key isEqualToString:@"httpProxy"]) {
		return self.httpProxy;
	}
	return nil;
}
- (void)setSpecialValue:(id)value forKey:(NSString *)key {
	if ([key isEqualToString:@"TrustAllKeys"]) {
		[self.gpgConf setValue:[value intValue] ? @"always" : nil forKey:@"trust-model"];
	} else if ([key isEqualToString:@"PassphraseCacheTime"]) {
		int cacheTime = [value intValue];
		
		BOOL oldAutoSave = self.gpgAgentConf.autoSave;
		[self.gpgAgentConf setAutoSave:NO];
		[self.gpgAgentConf setValue:[NSString stringWithFormat:@"%i", cacheTime] forKey:@"default-cache-ttl"];
		[self.gpgAgentConf setValue:[NSString stringWithFormat:@"%i", cacheTime * 12] forKey:@"max-cache-ttl"];		
		[self.gpgAgentConf setAutoSave:oldAutoSave];
		if (oldAutoSave) {
			[self.gpgAgentConf saveConfig];
		}
		
		[self valueChanged:[NSString stringWithFormat:@"%i", cacheTime] forKey:@"default-cache-ttl" inDomain:GPGDomain_gpgAgentConf];
		[self valueChanged:[NSString stringWithFormat:@"%i", cacheTime * 12] forKey:@"max-cache-ttl" inDomain:GPGDomain_gpgAgentConf];
	}
}


- (id)valueInStandardDefaultsForKey:(NSString *)key {
	return [[NSUserDefaults standardUserDefaults] objectForKey:key];
}
- (void)setValueInStandardDefaults:(id)value forKey:(NSString *)key {
	[[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
	[self valueChanged:value forKey:key inDomain:GPGDomain_standard];
}


- (id)valueInCommonDefaultsForKey:(NSString *)key {
	return [self.commonDefaults objectForKey:key];
}
- (void)setValueInCommonDefaults:(id)value forKey:(NSString *)key {
    NSObject *oldValue = [self.commonDefaults objectForKey:key];
	if(value != oldValue && ![value isEqual:oldValue]) {
		[self.commonDefaults setObject:value forKey:key];
		[self autoSaveCommonDefaults];
		[self valueChanged:value forKey:key inDomain:GPGDomain_common];
	}
}
- (void)autoSaveCommonDefaults {
	if (autoSave) {
		[self saveCommonDefaults];
	}
}
- (void)saveCommonDefaults {
	[[NSUserDefaults standardUserDefaults] setPersistentDomain:commonDefaults forName:commonDefaultsDomain];
}
- (void)loadCommonDefaults {
	commonDefaults = [[NSMutableDictionary alloc] initWithDictionary:[[NSUserDefaults standardUserDefaults] persistentDomainForName:commonDefaultsDomain]]; 
}
- (NSMutableDictionary *)commonDefaults {
	if (!commonDefaults) {
		[self loadCommonDefaults];
	}
	return [[commonDefaults retain] autorelease];
}


- (id)valueInEnvironmentForKey:(NSString *)key {
	NSObject *value = [[[NSProcessInfo processInfo] environment] objectForKey:key];
	if (!value) {
		value = [self.environment objectForKey:key];
	}
	return value;
}
- (void)setValueInEnvironment:(id)value forKey:(NSString *)key {
	setenv([key UTF8String], [[value description] UTF8String], YES);
	
    NSObject *oldValue = [self.environment objectForKey:key];
	if(value != oldValue && ![value isEqual:oldValue]) {
		[self.environment setObject:value forKey:key];
		[self autoSaveEnvironment];
		[self valueChanged:value forKey:key inDomain:GPGDomain_environment];
	}
}
- (void)autoSaveEnvironment {
	if (autoSave) {
		[self saveEnvironment];
	}
}
- (void)saveEnvironment {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	BOOL isDirectory;
	
	if ([fileManager fileExistsAtPath:environmentPlistDir isDirectory:&isDirectory]) {
		if (!isDirectory) {
			NSAssert1(isDirectory, @"'%@' is not a directory.", environmentPlistDir);
		}
	} else {
		NSAssert1([fileManager createDirectoryAtPath:environmentPlistDir attributes:nil], @"Unable to create directory '%@'", environmentPlistDir);
	}
	NSAssert1([self.environment writeToFile:environmentPlistPath atomically:YES], @"Unable to write file '%@'", environmentPlistPath);
}
- (void)loadEnvironment {
	environment = [[NSMutableDictionary alloc] initWithContentsOfFile:environmentPlistPath];
	if (!environment) {
		environment = [[NSMutableDictionary alloc] init];
	}
}
- (NSMutableDictionary *)environment {
	if (!environment) {
		[self loadEnvironment];
	}
	return [[environment retain] autorelease];
}



- (id)valueInGPGConfForKey:(NSString *)key {
	return [self.gpgConf valueForKey:key];
}
- (void)setValueInGPGConf:(id)value forKey:(NSString *)key {
	[self.gpgConf setValue:value forKey:key];
}
- (id)valueInGPGAgentConfForKey:(NSString *)key {
	return [self.gpgAgentConf valueForKey:key];
}
- (void)setValueInGPGAgentConf:(id)value forKey:(NSString *)key {
	[self.gpgAgentConf setValue:value forKey:key];
}


- (GPGConf *)gpgConf {
	if (!gpgConf) {
		gpgConf = [[GPGConf alloc] initWithPath:[[self gpgHome] stringByAppendingPathComponent:@"gpg.conf"]];
	}
	return [[gpgConf retain] autorelease];
}
- (GPGConf *)gpgAgentConf {
	if (!gpgAgentConf) {
		gpgAgentConf = [[GPGConf alloc] initWithPath:[[self gpgHome] stringByAppendingPathComponent:@"gpg-agent.conf"]];
	}
	return [[gpgAgentConf retain] autorelease];
}

- (GPGOptionsDomain)domainForKey:(NSString *)key {
	NSString *searchString = [NSString stringWithFormat:@"|%@|", key];
	for (NSNumber *key in domainKeys) {
		NSString *keys = [domainKeys objectForKey:key];
		if ([keys rangeOfString:searchString].length > 0) {
			return [key intValue];
		}
	}
	return GPGDomain_standard;
}

- (NSString *)gpgHome {
	NSString *path = [self valueInEnvironmentForKey:@"GNUPGHOME"];
	if (!path) {
		path = [NSHomeDirectory() stringByAppendingPathComponent:@".gnupg"];
	}
	return path;
}


- (NSString *)httpProxy {
	if (!httpProxy) {
		NSDictionary *proxyConfig = (NSDictionary *)SCDynamicStoreCopyProxies(nil);
		if ([[proxyConfig objectForKey:@"HTTPEnable"] intValue]) {
			httpProxy = [[NSString alloc] initWithFormat:@"%@:%@", [proxyConfig objectForKey:@"HTTPProxy"], [proxyConfig objectForKey:@"HTTPPort"]];
		} else {
			httpProxy = @"";
		}
	}
	return [[httpProxy retain] autorelease];
}

void SystemConfigurationDidChange(SCPreferencesRef prefs, SCPreferencesNotification notificationType, void *info) {
	if (notificationType & kSCPreferencesNotificationApply) {
		[((GPGOptions *)info)->httpProxy release];
		((GPGOptions *)info)->httpProxy = nil;
	}
}
- (void)initSystemConfigurationWatch {
	SCPreferencesContext context = {0, self, nil, nil, nil};
    SCPreferencesRef preferences = SCPreferencesCreate(nil, (CFStringRef)[[NSProcessInfo processInfo] processName], nil);
    SCPreferencesSetCallback(preferences, SystemConfigurationDidChange, &context);
    SCPreferencesScheduleWithRunLoop(preferences, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	CFRelease(preferences);
}	


- (void)valueChanged:(id)value forKey:(NSString *)key inDomain:(GPGOptionsDomain)domain {
	if (!updating) {
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:key, @"key", value, @"value", [NSNumber numberWithInt:domain], @"domain", nil];
		NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
		[center postNotificationName:GPGOptionsChangedNotification object:identifier userInfo:userInfo options:NSNotificationPostToAllSessions];		
	}
}
- (void)valueChangedNotification:(NSNotification *)notification {
	if (self != notification.object && ![identifier isEqualTo:notification.object]) {
		NSDictionary *userInfo = notification.userInfo;
		BOOL oldAutoSave = self.autoSave;
		self.autoSave = NO;
		updating++;
		NSString *key = [userInfo objectForKey:@"key"];
		[self willChangeValueForKey:key];
		[self setValue:[userInfo objectForKey:@"value"] forKey:key inDomain:[[userInfo objectForKey:@"domain"] intValue]];
		[self didChangeValueForKey:key];
		updating--;
		self.autoSave = oldAutoSave;
	}
}


+ (NSString *)standardizedKey:(NSString *)key {
	if ([key rangeOfString:@"_"].length > 0) {
		return [key stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
	}
	return key;
}




+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
	NSString *affectingKey = nil;
	if ([key rangeOfString:@"_"].length > 0) {
		NSCharacterSet *set = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz_"] invertedSet];
		if ([key rangeOfCharacterFromSet:set].length == 0) {
			affectingKey = [self standardizedKey:key];
		}
	}
	if (!affectingKey) {
		if ([key isEqualToString:@"TrustAllKeys"]) {
			affectingKey = @"trust-model";
		} else if ([key isEqualToString:@"PassphraseCacheTime"]) {
			affectingKey = @"default-cache-ttl";
		}
	}
	if (affectingKey) {
		return [NSSet setWithObject:affectingKey];
	} else {
		return [super keyPathsForValuesAffectingValueForKey:key];
	}
}


+ (void)initialize {
	environmentPlistDir = [[NSHomeDirectory() stringByAppendingPathComponent:@".MacOSX"] retain];
	environmentPlistPath = [[environmentPlistDir stringByAppendingPathComponent:@"environment.plist"] retain];

	NSString *gpgConfKeys = @"|agent-program|allow-freeform-uid|allow-multiple-messages|allow-multisig-verification|allow-non-selfsigned-uid|allow-secret-key-import|always-trust|armor|"
	"armour|ask-cert-expire|ask-cert-level|ask-sig-expire|attribute-fd|attribute-file|auto-check-trustdb|auto-key-locate|auto-key-retrieve|bzip2-compress-level|bzip2-decompress-lowmem|"
	"cert-digest-algo|cert-notation|cert-policy-url|charset|check-sig|cipher-algo|command-fd|command-file|comment|completes-needed|compress-algo|compress-keys|compress-level|"
	"compress-sigs|compression-algo|debug-quick-random|default-cert-check-level|default-cert-expire|default-cert-level|default-comment|default-key|default-keyserver-url|"
	"default-preference-list|default-recipient|default-recipient-self|default-sig-expire|digest-algo|disable-cipher-algo|disable-dsa2|disable-mdc|disable-pubkey-algo|display-charset|"
	"dry-run|emit-version|enable-dsa2|enable-progress-filter|enable-special-filenames|encrypt-to|escape-from-lines|exec-path|exit-on-status-write-error|expert|export-options|"
	"fast-list-mode|fixed-list-mode|for-your-eyes-only|force-mdc|force-ownertrust|force-v3-sigs|force-v4-certs|gnupg|gpg-agent-info|group|hidden-encrypt-to|hidden-recipient|"
	"honor-http-proxy|ignore-crc-error|ignore-mdc-error|ignore-time-conflict|ignore-valid-from|import-options|interactive|keyid-format|keyring|keyserver|keyserver-options|"
	"limit-card-insert-tries|list-key|list-only|list-options|list-sig|load-extension|local-user|lock-multiple|lock-never|lock-once|logger-fd|logger-file|mangle-dos-filenames|"
	"marginals-needed|max-cert-depth|max-output|merge-only|min-cert-level|multifile|no|no-allow-freeform-uid|no-allow-multiple-messages|no-allow-non-selfsigned-uid|no-armor|no-armour|"
	"no-ask-cert-expire|no-ask-cert-level|no-ask-sig-expire|no-auto-check-trustdb|no-auto-key-locate|no-auto-key-retrieve|no-batch|no-comments|no-default-keyring|no-default-recipient|"
	"no-disable-mdc|no-emit-version|no-encrypt-to|no-escape-from-lines|no-expensive-trust-checks|no-expert|no-for-your-eyes-only|no-force-mdc|no-force-v3-sigs|no-force-v4-certs|"
	"no-greeting|no-groups|no-literal|no-mangle-dos-filenames|no-mdc-warning|no-options|no-permission-warning|no-pgp2|no-pgp6|no-pgp7|no-pgp8|no-random-seed-file|no-require-backsigs|"
	"no-require-cross-certification|no-require-secmem|no-rfc2440-text|no-secmem-warning|no-show-notation|no-show-photos|no-show-policy-url|no-sig-cache|no-sig-create-check|"
	"no-sk-comments|no-skip-hidden-recipients|no-strict|no-textmode|no-throw-keyid|no-throw-keyids|no-tty|no-use-agent|no-use-embedded-filename|no-utf8-strings|no-verbose|no-version|"
	"not-dash-escaped|notation-data|openpgp|output|override-session-key|passphrase|passphrase-fd|passphrase-file|passphrase-repeat|personal-cipher-preferences|personal-cipher-prefs|"
	"personal-compress-preferences|personal-compress-prefs|personal-digest-preferences|personal-digest-prefs|pgp2|pgp6|pgp7|pgp8|photo-viewer|preserve-permissions|primary-keyring|"
	"recipient|remote-user|require-backsigs|require-cross-certification|require-secmem|rfc1991|rfc2440|rfc2440-text|rfc4880|s2k-cipher-algo|s2k-count|s2k-digest-algo|s2k-mode|"
	"secret-keyring|set-filename|set-filesize|set-notation|set-policy-url|show-keyring|show-notation|show-photos|show-policy-url|show-session-key|sig-keyserver-url|sig-notation|"
	"sig-policy-url|sign-with|simple-sk-checksum|sk-comments|skip-hidden-recipients|skip-verify|status-fd|status-file|strict|temp-directory|textmode|throw-keyid|throw-keyids|"
	"trust-model|trustdb-name|trusted-key|try-all-secrets|ungroup|use-agent|use-embedded-filename|user|utf8-strings|verify-options|with-colons|with-fingerprint|with-key-data|"
	"with-sig-check|with-sig-list|yes|";
	NSString *gpgAgentConfKeys = @"|allow-mark-trusted|allow-preset-passphrase|check-passphrase-pattern|csh|daemon|debug-wait|default-cache-ttl|default-cache-ttl-ssh|disable-scdaemon|"
	"enable-passphrase-history|enable-ssh-support|enforce-passphrase-constraints|faked-system-time|ignore-cache-for-signing|keep-display|keep-tty|max-cache-ttl|max-cache-ttl-ssh|"
	"max-passphrase-days|min-passphrase-len|min-passphrase-nonalpha|no-detach|no-grab|no-use-standard-socket|pinentry-program|pinentry-touch-file|scdaemon-program|server|sh|"
	"use-standard-socket|write-env-file|";
	NSString *environmentKeys = @"|GNUPGHOME|GPG_AGENT_INFO|";
	NSString *commonKeys = @"|UseKeychain|ShowPassphrase|PathToGPG|";
	NSString *specialKeys = @"|TrustAllKeys|PassphraseCacheTime|httpProxy|";
	
					
	domainKeys = [[NSDictionary alloc] initWithObjectsAndKeys:
				  gpgConfKeys, [NSNumber numberWithInt:GPGDomain_gpgConf], 
				  gpgAgentConfKeys, [NSNumber numberWithInt:GPGDomain_gpgAgentConf],
				  environmentKeys, [NSNumber numberWithInt:GPGDomain_environment],
				  commonKeys, [NSNumber numberWithInt:GPGDomain_common],
				  specialKeys, [NSNumber numberWithInt:GPGDomain_special],				  
				  nil];
}
+ (id)sharedOptions {
    if (!_sharedInstance) {
        _sharedInstance = [[super allocWithZone:nil] init];
    }
    return _sharedInstance;	
}
- (id)init {
	if (!initialized) {
		initialized = YES;
		autoSave = YES;
		identifier = [[NSString alloc] initWithFormat:@"%i%p", [[NSProcessInfo processInfo] processIdentifier], self];
		[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(valueChangedNotification:) name:GPGOptionsChangedNotification object:nil];
		[self initSystemConfigurationWatch];
	}
	return self;
}

+ (id)allocWithZone:(NSZone *)zone {
    return [[self sharedOptions] retain];	
}
- (id)copyWithZone:(NSZone *)zone {
    return self;
}
- (id)retain {
    return self;
}
- (NSUInteger)retainCount {
    return NSUIntegerMax;
}
- (void)release {
}
- (id)autorelease {
    return self;
}

@end
