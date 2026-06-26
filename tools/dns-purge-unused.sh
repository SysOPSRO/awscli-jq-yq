#!/bin/zsh

if [[ -z "$1" || -z "$2" ]]; then
    echo "Error: No domain provided."
    echo "Usage: $0 <domain> '<valid-regex-for-names-to-delete>' [FORCE]"
    exit 1
fi

DOMAIN="$1"
ZONE_FILE="${DOMAIN}"
VALID_REGEX="$2"

[[ -z "$3" ]] && { FORCE=0; } || { FORCE="1"; }

r53uniq() {
    local d="$1"
    awk -v d="$d" '!/^null/ {
        gsub("\."d,"", $0);
        split($0, lst, ",");
        for (i in lst) {
            x=lst[i];
            if (x != "" && !map[x]++) { print x }
        }
    }'
}

echo "Exporting current zone for $DOMAIN..."
cli53 export "$DOMAIN" > "$ZONE_FILE"

echo "Extracting active Service and Ingress hostnames for $DOMAIN..."
export SVC="$(kubectl get svc -o yaml -A | yq -r '.items[]|.metadata.annotations.external-dns*' | r53uniq "$DOMAIN" | xargs -r | sed 's% %|%g')"
export ING="$(kubectl get ing -o yaml -A | yq -r '.items[]|.metadata.annotations|."external-dns.alpha.kubernetes.io/hostname",."nginx.ingress.kubernetes.io/server-alias"' | r53uniq "$DOMAIN" | xargs -r | sed 's%[\ ,]%|%g')"
# the below can also get other ingresses (public) that are not configured with external dns annotations or server alias.
# filter for internal: |select(.metadata.annotations."kubernetes.io/ingress.class"=="nginx-internal")
export OTHER_ING="$(kubectl get ing -o yaml -A | yq -r '.items[]|.spec.rules[].host,.spec.tls[].hosts[]' | r53uniq "$DOMAIN" | xargs -r | sed 's%[\ ,]%|%g')"

COMMANDS_FILE=$(mktemp)
TOTAL_RECORDS=$(grep -cE '^[^;]' "$ZONE_FILE" || echo 0)
export DOMAIN
export VALID_REGEX
perl -lne '
    use Env;
    our $fqdn_re;
    BEGIN {
        sub escape_wildcards {
            my $s = shift;
            $s = quotemeta($s);
            $s =~ s/\\\*/.*/g;
            return $s;
        }

        my @svc_p = grep { $_ ne "" } map { escape_wildcards($_) } split(/\|/, $ENV{SVC});
        my @ing_p = grep { $_ ne "" } map { escape_wildcards($_) } split(/\|/, $ENV{ING});
        my @other_ing = grep { $_ ne "" } map { escape_wildcards($_) } split(/\|/, $ENV{OTHER_ING});
        my @all_p = do { my %seen; grep { !$seen{$_}++ } (@svc_p, @ing_p, @other_ing) };
        if (@all_p) {
            my $pattern_str = join("|", @all_p);
            # original
            # $fqdn_re = eval "qr#$pattern_str#";
            # less greedy
            $fqdn_re = eval "qr/^(?:$pattern_str)\$/";
        } else {
            $fqdn_re = qr/$.^/; # Match nothing
        }
    }
    @dns = split(/\t/);
    next unless @dns >= 4;

    $name = $dns[0];
    $type = $dns[3];
    # 1. Check if it is a target type
    # 2. Check if it is in a target subdomain
    # 3. Check if it is NOT in the SVC/ING list
    if ($type =~ /^(?:TXT|A|ALIAS|CNAME)$/ &&
        $name =~ /$ENV{VALID_REGEX}/) {
        my $is_active = 0;
        if ($fqdn_re) {
            # We use a simple regex match here.
            # If it matches any of our patterns, it is active.
            if ($name =~ $fqdn_re) {
                $is_active = 1;
            }
        }

        if (!$is_active) {
            print "$name\t$type";
        }
    }
' "$ZONE_FILE" > "$COMMANDS_FILE"

to_delete_count=$(wc -l < "$COMMANDS_FILE" | tr -d ' ')
# Prevent mass deletion if regex fails
if [[ $to_delete_count -gt 0 && $(( to_delete_count * 100 / TOTAL_RECORDS )) -gt 90 && $FORCE -eq 0 ]]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "CRITICAL ERROR: MASS DELETION DETECTED!"
    echo "Attempting to delete $((to_delete_count * 100 / TOTAL_RECORDS))% of the zone."
    echo "This is likely due to a regex mismatch. ABORTING."
    echo "First 5 records identified for deletion:"
    head -n 5 "$COMMANDS_FILE"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    rm "$COMMANDS_FILE"
    exit 1
fi

actual_deleted=0
while IFS=$'\t' read -r rname rtype; do
    if [[ -n "$rname" && -n "$rtype" ]]; then
        echo "Removing record ${rname}, type ${rtype}"
        cli53 rrdelete $DOMAIN ${rname} ${rtype}
        if [[ "${rtype}" == "ALIAS" ]]; then
            cli53 rrdelete $DOMAIN ${rname} A
        fi
        ((actual_deleted++))
    fi
done < "$COMMANDS_FILE"

rm -f "$COMMANDS_FILE"
echo "Deleted ${actual_deleted} records from ${DOMAIN}."
echo "RUNDECK:DATA:deleted_records=${actual_deleted}"
